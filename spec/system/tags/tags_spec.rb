# frozen_string_literal: true

describe "Tags", type: :system do
  fab!(:user) { Fabricate(:user, trust_level: TrustLevel[1]) }
  fab!(:admin)

  fab!(:tag_one) { Fabricate(:tag, name: "tag-one") }
  fab!(:tag_two) { Fabricate(:tag, name: "tag-two") }
  fab!(:tag_three) { Fabricate(:tag, name: "tag-three") }

  fab!(:category)

  fab!(:topic_with_one_tag) do
    Fabricate(:topic, tags: [tag_one]).tap { |t| Fabricate(:post, topic: t) }
  end
  fab!(:topic_with_two_tags) do
    Fabricate(:topic, tags: [tag_one, tag_two]).tap { |t| Fabricate(:post, topic: t) }
  end
  fab!(:topic_with_no_tags) { Fabricate(:topic).tap { |t| Fabricate(:post, topic: t) } }
  fab!(:topic_in_category_with_tag) do
    Fabricate(:topic, category: category, tags: [tag_three]).tap { |t| Fabricate(:post, topic: t) }
  end
  fab!(:pm_with_tag) do
    Fabricate(:private_message_topic, tags: [tag_one], user: admin, recipient: user).tap do |t|
      Fabricate(:post, topic: t, user: admin)
    end
  end

  let(:discovery) { PageObjects::Pages::Discovery.new }
  let(:category_page) { PageObjects::Pages::Category.new }
  let(:tag_page) { PageObjects::Pages::Tag.new }
  let(:user_private_messages_page) { PageObjects::Pages::UserPrivateMessages.new }

  before do
    SiteSetting.tagging_enabled = true
    SiteSetting.create_tag_allowed_groups = Group::AUTO_GROUPS[:trust_level_3]
    SiteSetting.tag_topic_allowed_groups = Group::AUTO_GROUPS[:trust_level_2]
    SiteSetting.pm_tags_allowed_for_groups = Group::AUTO_GROUPS[:trust_level_1]
    SiteSetting.personal_message_enabled_groups = Group::AUTO_GROUPS[:trust_level_1]
  end

  describe "discovery routes display tags" do
    it "displays tags on topics in the topic list" do
      sign_in(user)

      visit "/latest"

      # topic list has topic with tags
      expect(discovery.topic_list).to have_topic_tag(topic_with_one_tag, "tag-one")
      expect(discovery.topic_list).to have_topic_tags(topic_with_two_tags, "tag-one", "tag-two")
      expect(discovery.topic_list).to have_no_topic_tags(topic_with_no_tags)

      # topic list navigate to tag discovery page
      discovery.topic_list.click_topic_tag(topic_with_one_tag, "tag-one")
      expect(page).to have_current_path("/tag/tag-one")
      expect(discovery.topic_list).to have_topic(topic_with_one_tag)

      # category page topic list has topic with tags
      category_page.visit(category)
      expect(discovery.topic_list).to have_topic_tag(topic_in_category_with_tag, "tag-three")

      # category page navigate to tag discovery page from category page
      discovery.topic_list.click_topic_tag(topic_in_category_with_tag, "tag-three")
      expect(page).to have_current_path("/tag/tag-three")
      expect(discovery.topic_list).to have_topic(topic_in_category_with_tag)

      # tag page topic list filters correctly
      tag_page.visit_tag(tag_one)

      expect(discovery.topic_list).to have_topic(topic_with_one_tag)
      expect(discovery.topic_list).to have_topic(topic_with_two_tags)
      expect(discovery.topic_list).to have_no_topic(topic_with_no_tags)
      expect(discovery.topic_list).to have_topic_tag(topic_with_one_tag, "tag-one")

      # tag page navigate to another tag page
      discovery.topic_list.click_topic_tag(topic_with_two_tags, "tag-two")
      expect(page).to have_current_path("/tag/tag-two")
      expect(discovery.topic_list).to have_topic(topic_with_two_tags)
      expect(discovery.topic_list).to have_no_topic(topic_with_one_tag)

      # user messages topic list has topic with tags
      user_private_messages_page.visit(user)

      expect(page).to have_css(".topic-list-item[data-topic-id='#{pm_with_tag.id}']")
      expect(page).to have_css(
        ".topic-list-item[data-topic-id='#{pm_with_tag.id}'] .discourse-tags .discourse-tag",
        text: "tag-one",
      )

      # user messages navigate to tag page from user messages
      find(
        ".topic-list-item[data-topic-id='#{pm_with_tag.id}'] .discourse-tags .discourse-tag",
        text: "tag-one",
      ).click
      expect(page).to have_current_path("/u/#{user.username}/messages/tags/tag-one")
    end
  end

  describe "create/edit topics and PMs with tags" do
    let(:topic_page) { PageObjects::Pages::Topic.new }
    let(:composer) { PageObjects::Components::Composer.new }
    let(:mini_tag_chooser) { PageObjects::Components::SelectKit.new(".mini-tag-chooser") }

    it "allows creation and editing of topics with tags" do
      sign_in(admin)

      # create topic with two tags
      visit "/new-topic"
      expect(composer).to be_opened

      composer.fill_title("Topic with tags test")
      composer.fill_content("This is a test topic with tags")

      find(".mini-tag-chooser").click
      find(".mini-tag-chooser .filter-input").fill_in(with: "tag-one")
      find(".select-kit-row[data-name='tag-one']").click
      find(".mini-tag-chooser .filter-input").fill_in(with: "tag-two")
      find(".select-kit-row[data-name='tag-two']").click
      find(".mini-tag-chooser .filter-input").send_keys(:escape)

      composer.submit

      # ensure tags shown in topic view
      expect(page).to have_css("#topic-title")
      expect(topic_page.topic_tags).to include("tag-one", "tag-two")

      # edit topic tags - remove one and add one
      topic_page.click_topic_edit_title
      expect(topic_page).to have_topic_title_editor

      edit_tag_chooser = PageObjects::Components::SelectKit.new("#topic-title .mini-tag-chooser")
      edit_tag_chooser.expand
      edit_tag_chooser.search("tag-two")
      # use data-name since mini-tag-chooser uses IDs as values
      find(".selected-choice[data-name='tag-two']", wait: 5).click
      edit_tag_chooser.select_row_by_name("tag-three")

      find("#topic-title .submit-edit").click

      # ensure new tags reflected
      expect(topic_page.topic_tags).to include("tag-one", "tag-three")
      expect(topic_page.topic_tags).not_to include("tag-two")
    end

    it "allows creation and editing of PMs with tags" do
      sign_in(admin)

      # create PM with two tags
      visit "/new-message"
      expect(composer).to be_opened

      composer.fill_title("PM with tags test")
      composer.fill_content("This is a test PM with tags")
      composer.select_pm_user(user.username)

      find(".mini-tag-chooser").click
      find(".mini-tag-chooser .filter-input").fill_in(with: "tag-one")
      find(".select-kit-row[data-name='tag-one']").click
      find(".mini-tag-chooser .filter-input").fill_in(with: "tag-two")
      find(".select-kit-row[data-name='tag-two']").click
      find(".mini-tag-chooser .filter-input").send_keys(:escape)

      composer.submit

      # ensure tags shown in PM view
      expect(page).to have_css("#topic-title")
      expect(topic_page.topic_tags).to include("tag-one", "tag-two")

      # edit PM tags - remove one and add one
      topic_page.click_topic_edit_title
      expect(topic_page).to have_topic_title_editor

      edit_tag_chooser = PageObjects::Components::SelectKit.new("#topic-title .mini-tag-chooser")
      edit_tag_chooser.expand
      edit_tag_chooser.search("tag-two")
      # use data-name since mini-tag-chooser uses IDs as values
      find(".selected-choice[data-name='tag-two']", wait: 5).click
      edit_tag_chooser.select_row_by_name("tag-three")

      find("#topic-title .submit-edit").click

      # ensure new tags reflected
      expect(topic_page.topic_tags).to include("tag-one", "tag-three")
      expect(topic_page.topic_tags).not_to include("tag-two")
    end
  end
end
