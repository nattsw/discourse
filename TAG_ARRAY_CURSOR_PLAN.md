# Tag Array Cursor Plan

## Goal
Transform `top_tags` arrays from strings `["sushi", "coriander"]` to objects `[{id: 12, name: "sushi"}, {id: 14, name: "coriander"}]` in topic lists and site serializers.

**Note**: For a comprehensive inventory of ALL tag arrays in the codebase, see `TAG_ARRAYS_INVENTORY.md`. This plan is intentionally scoped to `top_tags` only.

## Scope Decision

After comprehensive analysis (see `TAG_ARRAYS_INVENTORY.md`), this plan focuses **ONLY on `top_tags`** for the following reasons:

1. **`top_tags` is isolated**: It's separate from topic tags and used primarily by `tag-drop.js` which already handles both formats
2. **Topic tags are inconsistent**: `TopicTagsMixin#tags` returns strings, but some components (like `tag-list.gjs`) expect objects - this is a separate issue
3. **Other tag arrays have mixed formats**: Some already return objects (via `TagSerializer`), some return strings - changing all would be a massive scope increase
4. **Frontend impact is minimal**: `tag-drop.js` already has fallback logic for both string and object formats

**This plan does NOT address**:
- Topic tags (`TopicTagsMixin#tags`) - returns strings, used by `render-tags.js` which expects strings
- Tag filtering in `TopicQuery`/`TopicQueryParams` - these handle filtering topics BY tags (input), not displaying popular tags (output)
- Other tag arrays like `TagGroupSerializer#tag_names`, `EmbeddableHostSerializer#tags`, `SiteCategorySerializer#allowed_tags` - these have different use cases

**Future consideration**: If frontend components evolve to require tag IDs universally, a separate migration for `TopicTagsMixin#tags` may be needed, but that's out of scope for this change.

## Architecture Context
The flow from `list_controller.rb` to `top_tags`:
1. `list_controller.rb` calls `TopicQuery.new(user, list_opts).list_latest` (or other filters)
2. `TopicQuery#create_list` creates a `TopicList` object, passing `category_id` and `tag_ids` in options
3. `TopicList#top_tags` calls `Tag.top_tags` with category/guardian - it does NOT use the `tag_ids` from filtering
4. `TopicListSerializer` serializes `TopicList#top_tags` as the `top_tags` attribute

**Key Insight**: `TopicQuery` and `TopicQueryParams` handle tag filtering (which tags to filter topics by), while `top_tags` is about displaying popular tags (which tags to show in the UI). They are separate concerns, though `TopicQuery` does pass `category_id` which affects which top tags are shown.

## Current State
- `Tag.top_tags` in [app/models/tag.rb](app/models/tag.rb) (line 135-165) returns array of strings via `tag_names_with_counts.map { |row| row.tag_name }`
- `TopicList#top_tags` in [app/models/topic_list.rb](app/models/topic_list.rb) (line 65-69) forwards `Tag.top_tags` result, using category from `TopicQuery` options
- `SiteSerializer#top_tags` in [app/serializers/site_serializer.rb](app/serializers/site_serializer.rb) (line 251-253) forwards `Tag.top_tags` result
- `TopicListSerializer` in [app/serializers/topic_list_serializer.rb](app/serializers/topic_list_serializer.rb) exposes `top_tags` as attribute (line 8)
- Frontend `tag-drop.js` in [frontend/discourse/select-kit/components/tag-drop.js](frontend/discourse/select-kit/components/tag-drop.js) handles both strings and objects (line 181-186)
- `build-topic-route.js` in [frontend/discourse/app/routes/build-topic-route.js](frontend/discourse/app/routes/build-topic-route.js) sets `Site.top_tags` and `Site.category_top_tags` from `list.topic_list.top_tags` (line 74-79)

## Implementation Steps

### Phase 1: Backend Core Changes

1. **Update `Tag.top_tags` method** ([app/models/tag.rb](app/models/tag.rb))
   - Modify SQL query to select both `tags.id` and `tags.name` (currently only selects `tags.name as tag_name`)
   - Change return value from `tag_names_with_counts.map { |row| row.tag_name }` to `tag_names_with_counts.map { |row| { id: row.tag_id, name: row.tag_name } }`
   - Ensure ordering (count-desc, name-asc) is preserved

2. **Update `SiteSerializer#navigation_menu_site_top_tags`** ([app/serializers/site_serializer.rb](app/serializers/site_serializer.rb))
   - Currently extracts tag names from `top_tags` array and queries DB again (line 319-320)
   - Since `top_tags` will now contain objects with `id` and `name`, update to use the objects directly
   - Remove the `Tag.where(name: tag_names)` query and use `top_tags` objects directly
   - Update sorting logic to work with objects instead of strings

### Phase 2: Serializer Updates

3. **Verify `TopicListSerializer`** ([app/serializers/topic_list_serializer.rb](app/serializers/topic_list_serializer.rb))
   - No changes needed - it already forwards `object.top_tags` which will now return objects

4. **Verify `SiteSerializer#top_tags`** ([app/serializers/site_serializer.rb](app/serializers/site_serializer.rb))
   - No changes needed - it already forwards `Tag.top_tags` which will return objects

### Phase 3: Frontend Updates

5. **Update `tag-drop.js`** ([frontend/discourse/select-kit/components/tag-drop.js](frontend/discourse/select-kit/components/tag-drop.js))
   - Update `content` computed property (line 142-150) to handle objects instead of strings
   - Remove string-to-object conversion logic (line 181-186) since all tags will be objects
   - Ensure sorting works with objects (line 145-146)

6. **Update `build-topic-route.js`** ([frontend/discourse/app/routes/build-topic-route.js](frontend/discourse/app/routes/build-topic-route.js))
   - No changes needed - it just forwards the data from backend

### Phase 4: Test Updates

7. **Update `spec/models/tag_spec.rb`** ([spec/models/tag_spec.rb](spec/models/tag_spec.rb))
   - Update all `Tag.top_tags` expectations from string arrays to object arrays with `id` and `name`
   - Update assertions to check `tag[:name]` or `tag.name` instead of direct string comparison

8. **Update `spec/models/topic_list_spec.rb`** ([spec/models/topic_list_spec.rb](spec/models/topic_list_spec.rb))
   - Update `top_tags` expectations (line 65-66, 86, 90-91) to expect objects with `id` and `name`
   - Update assertions to check `tag[:name]` or `tag.name`

9. **Update `spec/serializers/site_serializer_spec.rb`** ([spec/serializers/site_serializer_spec.rb](spec/serializers/site_serializer_spec.rb))
   - Update any `top_tags` expectations to expect objects

10. **Update `frontend/discourse/tests/integration/components/select-kit/tag-drop-test.gjs`** ([frontend/discourse/tests/integration/components/select-kit/tag-drop-test.gjs](frontend/discourse/tests/integration/components/select-kit/tag-drop-test.gjs))
    - Update test setup (line 16) to use objects: `this.site.top_tags = [{id: 1, name: "jeff"}, ...]`

11. **Update API schema files**
    - Update [spec/requests/api/schemas/json/site_response.json](spec/requests/api/schemas/json/site_response.json) (line 474-479) to define `top_tags` as array of objects with `id` and `name`
    - Update [spec/requests/api/schemas/json/category_topics_response.json](spec/requests/api/schemas/json/category_topics_response.json) (line 48-51) to define `top_tags` as array of objects

### Phase 5: Additional Considerations

12. **Verify TopicQuery/TopicQueryParams boundary**
    - Confirm that `TopicQuery#filter_by_tags` and `TopicQueryParams#build_topic_list_options` don't need changes
    - These handle tag filtering (input), not `top_tags` display (output)
    - `TopicQuery` passes `category_id` to `TopicList` which affects `top_tags`, but that's already working correctly

13. **Check for other `top_tags` usages**
    - Search for other places that call `Tag.top_tags` or use `top_tags` from serializers
    - Verify they handle the new object format
    - Check plugin code that might cache or expect string arrays
    - Note: Other tag arrays (like `TopicTagsMixin#tags`) are out of scope - see `TAG_ARRAYS_INVENTORY.md` for full analysis

14. **Cache considerations**
    - Verify that cached responses (HTML preload, JSON responses) handle the new format correctly
    - Both `TopicListSerializer` and `SiteSerializer` use `top_tags`, ensure both paths work
    - Check if any plugin code caches or expects string arrays

## Risks & Notes
- The SQL query in `Tag.top_tags` needs to select `tags.id` - verify the query structure allows this (currently only selects `tags.name`)
- `navigation_menu_site_top_tags` currently queries the DB again - this can be optimized to use the objects directly
- Frontend `tag-drop.js` already has fallback logic for strings - this can be removed after migration
- Keep the current ordering (count-desc, name-asc) as UI relies on it
- Both HTML and JSON routes use the same serializers, so changes will affect both
- Consider multisite safety - ensure tag IDs are consistent across sites if applicable
- `TopicQuery` and `TopicQueryParams` are large, complex systems but don't need changes - they handle tag filtering, not `top_tags` display
- **Scope is intentionally limited**: Only `top_tags` changes to objects. Other tag arrays (topic tags via `TopicTagsMixin`, tag group names, etc.) remain as strings. See `TAG_ARRAYS_INVENTORY.md` for full analysis of all tag arrays.
- **Inconsistency note**: `TopicTagsMixin#tags` returns strings, but `tag-list.gjs` expects objects - this is a separate pre-existing issue, not caused by this change

## Implementation Todos

1. **update-tag-top-tags**: Update Tag.top_tags in app/models/tag.rb to return objects with id and name instead of strings

2. **update-navigation-menu-tags**: Update SiteSerializer#navigation_menu_site_top_tags to use top_tags objects directly instead of querying DB again (depends on: update-tag-top-tags)

3. **update-tag-drop-frontend**: Update tag-drop.js frontend component to handle objects and remove string fallback logic (depends on: update-tag-top-tags)

4. **update-tag-specs**: Update spec/models/tag_spec.rb to expect objects with id and name (depends on: update-tag-top-tags)

5. **update-topic-list-specs**: Update spec/models/topic_list_spec.rb to expect objects with id and name (depends on: update-tag-top-tags)

6. **update-frontend-tests**: Update frontend tag-drop-test.gjs to use objects in test setup (depends on: update-tag-drop-frontend)

7. **update-api-schemas**: Update API schema JSON files to define top_tags as array of objects (depends on: update-tag-top-tags)

8. **verify-other-endpoints**: Search for other endpoints returning tag arrays as strings and update if needed (depends on: update-tag-top-tags)

