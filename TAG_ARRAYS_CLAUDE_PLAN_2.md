# Fix TopicTrackingState Tag Migration

## Overview

Complete the tag string-to-object migration by fixing TopicTrackingState MessageBus payloads. Currently, TopicTrackingState sends tag names as strings instead of tag objects, causing console.warn statements to fire in 9 locations across the frontend.

**Root Cause**: `app/models/topic_tracking_state.rb` uses `topic.tags.pluck(:id, :name).transpose` which creates separate arrays instead of tag objects.

**Impact**: Low-risk, isolated change. Console warnings will stop firing once backend sends tag objects.

## User Decisions

- **Console.warn**: Keep statements as safeguards (user wants to see them during manual testing)
- **Backward compatibility**: Keep `topic_tag_ids` field in payloads
- **Testing**: Add comprehensive tests for tag objects in MessageBus payloads

## Implementation Steps

### 1. Backend: Update TopicTrackingState.rb

**File**: `app/models/topic_tracking_state.rb`

#### Change 1: `publish_new` method (lines 45-59)

```ruby
# Line 45-46: Change from transpose to map
# BEFORE:
tag_ids, tags = nil
tag_ids, tags = topic.tags.pluck(:id, :name).transpose if include_tags_in_report?

# AFTER:
tags = nil
tags = topic.tags.map { |tag| { id: tag.id, name: tag.name } } if include_tags_in_report?

# Line 57-59: Update payload
# BEFORE:
if tags
  payload[:tags] = tags
  payload[:topic_tag_ids] = tag_ids
end

# AFTER:
if tags
  payload[:tags] = tags  # Now array of objects
  payload[:topic_tag_ids] = tags.map { |t| t[:id] }  # Backward compatibility
end
```

#### Change 2: `publish_latest` method (lines 73-88)

```ruby
# Line 73-74: Change from transpose to map
# BEFORE:
tag_ids, tags = nil
tag_ids, tags = topic.tags.pluck(:id, :name).transpose if include_tags_in_report?

# AFTER:
tags = nil
tags = topic.tags.map { |tag| { id: tag.id, name: tag.name } } if include_tags_in_report?

# Line 86-88: Update payload
# BEFORE:
if tags
  message[:payload][:tags] = tags
  message[:payload][:topic_tag_ids] = tag_ids
end

# AFTER:
if tags
  message[:payload][:tags] = tags  # Now array of objects
  message[:payload][:topic_tag_ids] = tags.map { |t| t[:id] }  # Backward compatibility
end
```

#### Change 3: `publish_unread` method (lines 144-181)

```ruby
# Line 144-146: Change from transpose to map
# BEFORE:
tags = nil
tag_ids = nil
tag_ids, tags = post.topic.tags.pluck(:id, :name).transpose if include_tags_in_report?

# AFTER:
tags = nil
tags = post.topic.tags.map { |tag| { id: tag.id, name: tag.name } } if include_tags_in_report?

# Line 179-181: Update payload
# BEFORE:
if tags
  payload[:tags] = tags
  payload[:topic_tag_ids] = tag_ids
end

# AFTER:
if tags
  payload[:tags] = tags  # Now array of objects
  payload[:topic_tag_ids] = tags.map { |t| t[:id] }  # Backward compatibility
end
```

**Summary**: 3 methods updated, 6 code blocks changed

### 2. Backend: Add Comprehensive Tests

**File**: `spec/models/topic_tracking_state_spec.rb`

Add new test contexts for each publish method to verify tag objects structure:

```ruby
describe ".publish_new with tags" do
  it "sends tags as array of objects with id and name" do
    SiteSetting.tagging_enabled = true
    tag1 = Fabricate(:tag, name: "foo")
    tag2 = Fabricate(:tag, name: "bar")
    topic.tags = [tag1, tag2]

    message = MessageBus.track_publish("/new") {
      described_class.publish_new(topic)
    }.first

    tags = message.data["payload"]["tags"]
    expect(tags).to be_an(Array)
    expect(tags.length).to eq(2)
    expect(tags[0]).to match(hash_including("id" => tag1.id, "name" => "foo"))
    expect(tags[1]).to match(hash_including("id" => tag2.id, "name" => "bar"))

    # Verify backward compatibility field
    expect(message.data["payload"]["topic_tag_ids"]).to match_array([tag1.id, tag2.id])
  end
end

describe ".publish_latest with tags" do
  it "sends tags as array of objects with id and name" do
    SiteSetting.tagging_enabled = true
    tag1 = Fabricate(:tag, name: "baz")
    topic.tags = [tag1]

    message = MessageBus.track_publish("/latest") {
      described_class.publish_latest(topic)
    }.first

    tags = message.data["payload"]["tags"]
    expect(tags).to be_an(Array)
    expect(tags.length).to eq(1)
    expect(tags[0]).to match(hash_including("id" => tag1.id, "name" => "baz"))
    expect(message.data["payload"]["topic_tag_ids"]).to eq([tag1.id])
  end
end

describe ".publish_unread with tags" do
  fab!(:other_user) { Fabricate(:user) }

  before do
    Fabricate(:topic_user_tracking, topic: post.topic, user: other_user)
  end

  it "sends tags as array of objects with id and name" do
    SiteSetting.tagging_enabled = true
    tag1 = Fabricate(:tag, name: "urgent")
    post.topic.tags = [tag1]

    message = MessageBus.track_publish("/unread") {
      described_class.publish_unread(post)
    }.first

    tags = message.data["payload"]["tags"]
    expect(tags).to be_an(Array)
    expect(tags.length).to eq(1)
    expect(tags[0]).to match(hash_including("id" => tag1.id, "name" => "urgent"))
    expect(message.data["payload"]["topic_tag_ids"]).to eq([tag1.id])
  end
end
```

### 3. Frontend: Update Test Mock Data

**File**: `frontend/discourse/tests/unit/models/topic-tracking-state-test.js`

Update tag mock data from strings to objects (lines 51, 57, 63, 69, 76):

```javascript
// BEFORE:
tags: ["foo", "baz"],

// AFTER:
tags: [{ id: 1, name: "foo" }, { id: 2, name: "baz" }],
```

Add new test for MessageBus payload handling:

```javascript
test("handles tag objects from MessageBus", function (assert) {
  const trackingState = TopicTrackingState.create();

  publishToMessageBus("/latest", {
    topic_id: 1,
    message_type: "latest",
    payload: {
      tags: [{ id: 1, name: "foo" }, { id: 2, name: "bar" }],
      topic_tag_ids: [1, 2],
      category_id: 1,
      archetype: "regular",
      bumped_at: new Date().toISOString(),
    },
  });

  const state = trackingState.findState(1);
  assert.ok(state, "state exists");
  assert.deepEqual(
    state.tags,
    [{ id: 1, name: "foo" }, { id: 2, name: "bar" }],
    "tags are objects with id and name"
  );
});
```

### 4. Console.warn Locations (Keep for Manual Testing)

**These files have console.warn statements - DO NOT REMOVE (per user request):**

1. `frontend/discourse/app/lib/render-tag.js` (lines 18-23)
2. `frontend/discourse/app/lib/render-tags.js` (lines 83-89)
3. `frontend/discourse/app/models/topic.js` (lines 454-461)
4. `frontend/discourse/app/models/topic-tracking-state.js` (lines 47-52, 66-71, 78-83)
5. `frontend/discourse/app/components/topic-list/item.gjs` (lines 62-74)
6. `frontend/discourse/app/components/topic-list/latest-topic-list-item.gjs` (lines 20-32)
7. `frontend/discourse/select-kit/components/topic-notifications-button.gjs` (lines 86-96)

**Keep these as-is** - user wants to manually verify they stop firing during testing.

## Testing Plan

### Backend Tests

```bash
bundle exec rspec spec/models/topic_tracking_state_spec.rb
```

Verify:
- New tag object tests pass
- Existing tests still pass
- No regressions in TopicTrackingState behavior

### Frontend Tests

```bash
yarn test --filter="topic-tracking-state"
```

Verify:
- Mock data updates work correctly
- New MessageBus payload test passes
- All existing tests pass

### Manual Integration Testing

1. **Real-time new topic**
   - User A creates topic with tags in one browser
   - User B on /latest in another browser
   - Verify: Topic appears, tags display correctly, NO console warnings

2. **Real-time unread updates**
   - User A replies to tagged topic
   - User B tracking topic
   - Verify: Unread count updates, NO console warnings

3. **Tag filtering**
   - Navigate to /tag/tagname
   - Create new topic with that tag
   - Verify: Incoming count updates, NO console warnings

4. **Browser console check**
   - Open dev tools console
   - Navigate: /latest, /new, /categories, /tag/foo
   - Create/reply to topics with tags
   - Verify: NO "Topic tag is a string" warnings appear

5. **MessageBus payload inspection**
   - Open Network tab, filter by "message-bus"
   - Create/update tagged topics
   - Inspect payload structure
   - Verify: `tags` field contains objects with `{id, name}`
   - Verify: `topic_tag_ids` field present for backward compatibility

## Success Criteria

- ✅ Backend tests pass with new tag object expectations
- ✅ Frontend tests pass with updated mock data
- ✅ NO console.warn statements fire during manual testing
- ✅ Tags display correctly in real-time updates
- ✅ Tag filtering works correctly
- ✅ MessageBus payloads contain tag objects
- ✅ `topic_tag_ids` field present for backward compatibility

## Rollback Plan

If issues discovered:
1. Revert TopicTrackingState.rb changes (use `git revert`)
2. Console warnings will return but functionality intact
3. Frontend defensive checks prevent breakage

## Files to Modify

**Must change:**
- `app/models/topic_tracking_state.rb` - 3 methods, 6 code blocks
- `spec/models/topic_tracking_state_spec.rb` - Add 3 new test contexts
- `frontend/discourse/tests/unit/models/topic-tracking-state-test.js` - Update mock data

**Do NOT change (per user request):**
- All files with console.warn statements (keep for manual verification)

## Notes

- Migration completes work started in commit 10bd35cd2ff6f78dd38cb7cb9d60ded248d69a3f
- Console.warn statements kept intentionally for user to manually verify during testing
- Backward compatible with `topic_tag_ids` field for plugins
- Low-risk change, isolated to TopicTrackingState
- Estimated time: 4-6 hours including testing
