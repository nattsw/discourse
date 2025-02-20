"use strict";

const EmberApp = require("ember-cli/lib/broccoli/ember-app");
const path = require("path");
const mergeTrees = require("broccoli-merge-trees");
const concat = require("broccoli-concat");
const { createI18nTree } = require("./lib/translation-plugin");
const { parsePluginClientSettings } = require("./lib/site-settings-plugin");
const discourseScss = require("./lib/discourse-scss");
const generateScriptsTree = require("./lib/scripts");
const funnel = require("broccoli-funnel");
const DeprecationSilencer = require("deprecation-silencer");
const generateWorkboxTree = require("./lib/workbox-tree-builder");

process.env.BROCCOLI_ENABLED_MEMOIZE = true;

module.exports = function (defaults) {
  const discourseRoot = path.resolve("../../../..");
  const vendorJs = discourseRoot + "/vendor/assets/javascripts/";

  // Silence deprecations which we are aware of - see `lib/deprecation-silencer.js`
  DeprecationSilencer.silence(console, "warn");
  DeprecationSilencer.silence(defaults.project.ui, "writeWarnLine");

  const isProduction = EmberApp.env().includes("production");
  const isTest = EmberApp.env().includes("test");

  const app = new EmberApp(defaults, {
    autoRun: false,
    "ember-qunit": {
      insertContentForTestBody: false,
    },
    sourcemaps: {
      // There seems to be a bug with broccoli-concat when sourcemaps are disabled
      // that causes the `app.import` statements below to fail in production mode.
      // This forces the use of `fast-sourcemap-concat` which works in production.
      enabled: true,
    },
    autoImport: {
      forbidEval: true,
      insertScriptsAt: "ember-auto-import-scripts",
      webpack: {
        // Workarounds for https://github.com/ef4/ember-auto-import/issues/519 and https://github.com/ef4/ember-auto-import/issues/478
        devtool: isProduction ? false : "source-map", // Sourcemaps contain reference to the ephemeral broccoli cache dir, which changes on every deploy
        optimization: {
          moduleIds: "size", // Consistent module references https://github.com/ef4/ember-auto-import/issues/478#issuecomment-1000526638
        },
        resolve: {
          fallback: {
            // Sinon needs a `util` polyfill
            util: require.resolve("util/"),
            // Also for sinon
            timers: false,
          },
        },
        module: {
          rules: [
            // Sinon/`util` polyfill accesses the `process` global,
            // so we need to provide a mock
            {
              test: require.resolve("util/"),
              use: [
                {
                  loader: "imports-loader",
                  options: {
                    additionalCode: "var process = { env: {} };",
                  },
                },
              ],
            },
          ],
        },
      },
    },
    fingerprint: {
      // Handled by Rails asset pipeline
      enabled: false,
    },
    SRI: {
      // We don't use SRI in Rails. Disable here to match:
      enabled: false,
    },

    "ember-cli-terser": {
      enabled: isProduction,
      exclude: [
        "**/test-*.js",
        "**/core-tests*.js",
        "**/highlightjs/*",
        "**/javascripts/*",
      ],
    },

    "ember-cli-babel": {
      throwUnlessParallelizable: true,
    },

    babel: {
      plugins: [require.resolve("deprecation-silencer")],
    },

    // We need to build tests in prod for theme tests
    tests: true,

    vendorFiles: {
      // Freedom patch - includes bug fix and async stack support
      // https://github.com/discourse/backburner.js/commits/discourse-patches
      backburner:
        "node_modules/@discourse/backburner.js/dist/named-amd/backburner.js",
    },
  });

  // WARNING: We should only import scripts here if they are not in NPM.
  // For example: our very specific version of bootstrap-modal.
  app.import(vendorJs + "bootbox.js");
  app.import("node_modules/bootstrap/js/modal.js");
  app.import(vendorJs + "caret_position.js");
  app.import("node_modules/ember-source/dist/ember-template-compiler.js", {
    type: "test",
  });
  app.import(discourseRoot + "/app/assets/javascripts/polyfills.js");

  app.import(
    discourseRoot +
      "/app/assets/javascripts/discourse/public/assets/scripts/module-shims.js"
  );

  const discoursePluginsTree = app.project
    .findAddonByName("discourse-plugins")
    .generatePluginsTree();

  const adminTree = app.project.findAddonByName("admin").treeForAddonBundle();

  const wizardTree = app.project.findAddonByName("wizard").treeForAddonBundle();

  const markdownItBundleTree = app.project
    .findAddonByName("pretty-text")
    .treeForMarkdownItBundle();

  let testemStylesheetTree;
  if (isTest) {
    testemStylesheetTree = mergeTrees([
      discourseScss(`${discourseRoot}/app/assets/stylesheets`, "qunit.scss"),
      discourseScss(
        `${discourseRoot}/app/assets/stylesheets`,
        "qunit-custom.scss"
      ),
    ]);
  }

  return app.toTree([
    createI18nTree(discourseRoot, vendorJs),
    parsePluginClientSettings(discourseRoot, vendorJs, app),
    funnel(`${discourseRoot}/public/javascripts`, { destDir: "javascripts" }),
    funnel(`${vendorJs}/highlightjs`, {
      files: ["highlight-test-bundle.min.js"],
      destDir: "assets/highlightjs",
    }),
    generateWorkboxTree(),
    concat(adminTree, {
      inputFiles: ["**/*.js"],
      outputFile: `assets/admin.js`,
    }),
    concat(wizardTree, {
      inputFiles: ["**/*.js"],
      outputFile: `assets/wizard.js`,
    }),
    concat(markdownItBundleTree, {
      inputFiles: ["**/*.js"],
      outputFile: `assets/markdown-it-bundle.js`,
    }),
    generateScriptsTree(app),
    discoursePluginsTree,
    testemStylesheetTree,
  ]);
};
