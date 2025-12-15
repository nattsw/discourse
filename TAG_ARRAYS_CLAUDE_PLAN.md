Tag Arrays Object Migration Plan

Overview

Migrate tag arrays from string format ["sushi", "coriander"] to object
format [{id: 12, name: "sushi"}, {id: 14, name: "coriander"}] for UI
components (dropdowns, filters, displayed tags, sidebar).

Scope: UI-focused changes. RSS feeds and webhooks maintain backward
compatibility.

 ---
Backend Changes

1. Update Tag.top_tags Method

File: app/models/tag.rb (lines 135-165)

Change SQL query to return both id and name:
tag_names_with_counts = DB.query <<~SQL
SELECT tags.id as tag_id, tags.name as tag_name, SUM(stats.topic_count)
AS sum_topic_count
FROM category_tag_stats stats
JOIN tags ON stats.tag_id = tags.id AND stats.topic_count > 0
WHERE stats.category_id in (#{scope_category_ids.join(",")})
#{filter_sql}
GROUP BY tags.id, tags.name
ORDER BY sum_topic_count DESC, tag_name ASC
LIMIT #{limit}
SQL

tag_names_with_counts.map { |row| { id: row.tag_id, name: row.tag_name }
}

Impact: Used by TopicList#top_tags, SiteSerializer#top_tags

2. Update TopicTagsMixin#tags

File: app/serializers/concerns/topic_tags_mixin.rb (lines 15-16)

Change from:
def tags
all_tags.map(&:name)
end

To:
def tags
all_tags.map { |tag| { id: tag.id, name: tag.name } }
end

Impact:
- Used by: TopicListItemSerializer, TopicViewSerializer,
  SearchTopicListItemSerializer, SuggestedTopicSerializer, bookmark
  serializers
- Affects ALL topic list endpoints (latest, new, top, unread, category
  lists, user activity, search)

3. Update tags_descriptions to use tag.name as key

File: app/serializers/concerns/topic_tags_mixin.rb (lines 19-24)

No changes needed - still uses tag.name as key, which works fine.

4. Optimize SiteSerializer#navigation_menu_site_top_tags (Optional)

File: app/serializers/site_serializer.rb (lines 317-327)

Currently makes extra DB query. Can optimize to use tag IDs from
top_tags:
def navigation_menu_site_top_tags
if top_tags.present?
top_tag_objects = top_tags[0...SIDEBAR_TOP_TAGS_TO_SHOW]
tag_ids = top_tag_objects.map { |t| t[:id] }
tags = Tag.where(id: tag_ids)
serialized = serialize_tags(tags)
serialized.sort_by { |tag| top_tag_objects.index { |t| t[:id] ==
tag[:id] } }
else
[]
end
end

 ---
Frontend Changes

1. Update render-tag.js helper

File: frontend/discourse/app/lib/render-tag.js (lines 18-19)

Change from:
const visibleName = escapeExpression(tag);
tag = visibleName.toLowerCase();

To:
const tagName = typeof tag === 'string' ? tag : tag.name;
const visibleName = escapeExpression(tagName);
const tagLower = visibleName.toLowerCase();

Then update references from tag to tagLower throughout the function.

2. Update render-tags.js helper

File: frontend/discourse/app/lib/render-tags.js (lines 82-90)

Change iteration to handle objects:
for (let i = 0; i < tags.length; i++) {
const tag = tags[i];
const tagName = typeof tag === 'string' ? tag : tag.name;

buffer += renderTag(tagName, {
...params,
tagClasses: params?.tagClasses?.[tagName],
description: topic?.tags_descriptions?.[tagName]
});
}

3. Update topic list components

File: frontend/discourse/app/components/topic-list/item.gjs (line 63)

Change:
get tagClassNames() {
return this.args.topic.tags?.map((tag) => {
const tagName = typeof tag === 'string' ? tag : tag.name;
return `tag-${tagName}`;
});
}

File:
frontend/discourse/app/components/topic-list/latest-topic-list-item.gjs
(line 21)

Same change as above.

4. Update topic tracking state

File: frontend/discourse/app/models/topic-tracking-state.js

Update tag comparison methods (lines 607, 706, 919):
// Helper function at top of file
function hasTagName(tags, tagName) {
if (!tags) return false;
return tags.some(tag => {
const name = typeof tag === 'string' ? tag : tag.name;
return name === tagName;
});
}

// Then use hasTagName(topic.tags, tagId) instead of
topic.tags?.includes(tagId)

5. Update topic model

File: frontend/discourse/app/models/topic.js (lines 445-461)

Update visibleListTags method:
@discourseComputed("tags")
visibleListTags(tags) {
if (!tags || !this.siteSettings.suppress_overlapping_tags_in_list) {
return tags;
}

const title = this.get("fancyTitle")?.toLowerCase();
const newTags = [];

tags.forEach(function (tag) {
const tagName = typeof tag === 'string' ? tag : tag.name;
if (!title.includes(tagName.toLowerCase())) {
newTags.push(tag);
}
});

return newTags;
}

6. Verify tag-drop.js component

File: frontend/discourse/select-kit/components/tag-drop.js (lines
181-186)

Already has dual support! No changes needed during migration.

After migration stabilizes, can remove string fallback:
return (this.content || []).map((tag) => {
return tag.id && tag.name ? tag : this.defaultItem(tag.name, tag.name);
});

7. Update select-kit tag components

File:
frontend/discourse/select-kit/components/topic-notifications-button.gjs
(line 86)

Change:
// Before
return !this.args.topic.tags.some((tag) => watchedTags.includes(tag));

// After
return !this.args.topic.tags.some((tag) => {
const tagName = typeof tag === 'string' ? tag : tag.name;
return watchedTags.includes(tagName);
});

 ---
Backward Compatibility for RSS/Webhooks

RSS Feed Templates (Keep strings)

RSS templates directly access topic.tags in ERB. Since we're changing
TopicTagsMixin#tags to return objects, we need to handle this in
templates.

Files to check:
- app/views/list/list.rss.erb
- app/views/topics/show.rss.erb

Pattern to search for:
<% topic.tags.each do |tag| %>

Update to:
<% topic.tags.each do |tag| %>
<% tag_name = tag.is_a?(Hash) ? tag[:name] : tag %>
   <!-- use tag_name -->
<% end %>

Webhooks (Add API versioning)

Webhooks use TopicSerializer which includes TopicTagsMixin. To maintain
backward compatibility:

Option A: Add serializer parameter (simpler):
# app/serializers/concerns/topic_tags_mixin.rb
def tags
if scope&.opts&.dig(:webhook_format) == true
# Legacy format for webhooks
all_tags.map(&:name)
else
# New object format
all_tags.map { |tag| { id: tag.id, name: tag.name } }
end
end

Option B: Skip webhook changes entirely
Since user specified "RSS and webhook not necessary", we can add the
serializer parameter and ensure webhooks pass webhook_format: true to
maintain strings.

 ---
Testing Strategy

Backend Tests

File: spec/models/tag_spec.rb (lines 119-160)

Update all Tag.top_tags expectations:
# Before
expect(Tag.top_tags(category: category1).sort).to eq([tags[0].name].sort)

# After
expect(Tag.top_tags(category: category1)).to match_array([
{ id: tags[0].id, name: tags[0].name }
])

File: spec/models/topic_list_spec.rb (lines 61-106)

Update topic_list.top_tags expectations to expect objects.

File: spec/serializers/topic_list_serializer_spec.rb

Add test for object format in serialized output.

Frontend Tests

File: frontend/discourse/tests/integration/components/select-kit/tag-drop
-test.gjs (line 16)

Update test data:
this.site.top_tags = [
{ id: 1, name: "jeff" },
{ id: 2, name: "neil" },
{ id: 3, name: "arpit" },
{ id: 4, name: "régis" }
];

Add tests for:
- Tag rendering with objects
- Tag filtering
- Tag selection
- Unicode tags
- Mobile view

API Schema Tests

Files:
- spec/requests/api/schemas/json/site_response.json (lines 474-479)
- spec/requests/api/schemas/json/category_topics_response.json (lines
  48-51)
- spec/requests/api/schemas/json/topic_list_response.json

Update top_tags schema:
"top_tags": {
"type": "array",
"items": {
"type": "object",
"properties": {
"id": { "type": "integer" },
"name": { "type": "string" }
},
"required": ["id", "name"]
}
}

Update tags schema in topic objects similarly.

 ---
Implementation Sequence

Phase 1: Backend Core (Days 1-2)

1. Update Tag.top_tags SQL query and return value
2. Update TopicTagsMixin#tags to return objects
3. Add backward compatibility for webhooks (serializer option)
4. Run backend test suite
5. Fix failing tag_spec.rb, topic_list_spec.rb tests

Phase 2: Frontend Rendering (Days 3-4)

1. Update render-tag.js to handle objects
2. Update render-tags.js to handle objects
3. Update topic list components (item.gjs, latest-topic-list-item.gjs)
4. Update topic-tracking-state.js comparison logic
5. Update topic.js model methods
6. Test locally on /latest page

Phase 3: Frontend Components (Day 5)

1. Update topic-notifications-button.gjs
2. Verify tag-drop.js still works (dual support)
3. Update any other select-kit components
4. Test tag dropdowns and filters
5. Test sidebar tag display

Phase 4: RSS/Webhook Compatibility (Day 6)

1. Update RSS ERB templates to extract tag names
2. Add webhook serializer option for backward compat
3. Test RSS feed generation
4. Verify webhook payloads (if needed)

Phase 5: Testing (Days 7-8)

1. Update all backend test expectations
2. Update all frontend test expectations
3. Update API schema tests
4. Add new integration tests
5. Manual testing:
- Topic list rendering (latest, new, top, unread)
- Tag dropdowns and filters
- Sidebar tags
- Category pages
- Search results
- User activity pages
- Mobile view (?mobile_view=1)
- RTL layout
- Dark mode

Phase 6: Validation (Days 9-10)

1. Performance benchmarks (no regression)
2. Review all changed files
3. Test with popular plugins
4. Final QA pass
5. Create PR with detailed description

 ---
Critical Files Summary

Must Change (Backend)

1. app/models/tag.rb - Tag.top_tags method
2. app/serializers/concerns/topic_tags_mixin.rb - tags method
3. app/serializers/site_serializer.rb - navigation_menu_site_top_tags
   (optional optimization)

Must Change (Frontend - Core)

1. frontend/discourse/app/lib/render-tag.js - tag rendering helper
2. frontend/discourse/app/lib/render-tags.js - tags rendering helper
3. frontend/discourse/app/models/topic-tracking-state.js - tag comparison
4. frontend/discourse/app/models/topic.js - visibleListTags method
5. frontend/discourse/app/components/topic-list/item.gjs - tag class
   names
6.
frontend/discourse/app/components/topic-list/latest-topic-list-item.gjs -
tag class names

Must Change (Frontend - Components)

7.
frontend/discourse/select-kit/components/topic-notifications-button.gjs -
tag matching

Must Update (Templates)

8. app/views/list/list.rss.erb - RSS feed (if uses tags)
9. app/views/topics/show.rss.erb - Topic RSS (if uses tags)

Must Update (Tests)

10. spec/models/tag_spec.rb - Tag.top_tags tests
11. spec/models/topic_list_spec.rb - TopicList#top_tags tests
12. spec/requests/api/schemas/json/site_response.json - API schema
13. spec/requests/api/schemas/json/category_topics_response.json - API
    schema
14. spec/requests/api/schemas/json/topic_list_response.json - API schema
15. frontend/discourse/tests/integration/components/select-kit/tag-drop-t
    est.gjs - Frontend tests

 ---
Edge Cases to Test

1. Empty tags: Sites/categories with no tags
2. Unicode tags: Tags with emoji, CJK characters, RTL text
3. Large datasets: 1000+ tags, performance impact
4. Permissions: Anonymous users, staff vs regular, private categories,
   hidden tags
5. Caching: Anonymous cache, category cache, site cache
6. Mobile: ?mobile_view=1, responsive layouts
7. Subfolders: Discourse hosted at /forum path
8. Multisite: Tag IDs are site-specific
9. Private messages: PM tags display
10. Deleted tags: Topics with deleted tags

 ---
Success Criteria

- ✅ All backend tests passing
- ✅ All frontend tests passing
- ✅ API schema tests passing
- ✅ No JS errors in console when browsing topics
- ✅ Tag dropdowns display and function correctly
- ✅ Topic tags display correctly in lists
- ✅ Sidebar tags work as expected
- ✅ RSS feeds generate without errors
- ✅ Webhooks maintain backward compatibility
- ✅ No performance regression on /latest or /site.json
- ✅ Mobile view works correctly
- ✅ Dark mode renders tags properly
- ✅ RTL layout handles tags correctly

 ---
Risk Assessment

Low Risk:
- Tag.top_tags change (isolated scope)
- Frontend rendering helpers (well-contained)
- Tag dropdown component (already has dual support)

Medium Risk:
- TopicTagsMixin change (affects many endpoints)
- Topic tracking state (tag comparison logic)
- API schema changes (external consumers)

High Risk:
- RSS template changes (parsing errors break feeds)
- Webhook backward compatibility (external integrations)

Mitigation:
- Thorough testing before merge
- Backward compatibility layers for RSS/webhooks
- Monitor error logs after deployment
- Have rollback plan ready
  ╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌

Would you like to proceed?

❯ 1. Yes, and auto-accept edits
2. Yes, and manually approve edits
3. Type here to tell Claude what to change

ctrl-g to edit in VS Code
