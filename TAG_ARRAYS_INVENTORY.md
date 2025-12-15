# Tag Arrays Inventory

## Summary
This document catalogs all tag arrays returned in API responses and used by frontend components. The key question: **Should we change ALL tag arrays to objects, or only `top_tags`?**

## Tag Arrays in API Responses

### 1. `top_tags` (Topic Lists & Site)
**Location**: `TopicListSerializer#top_tags`, `SiteSerializer#top_tags`
**Current Format**: `["sushi", "coriander"]` (array of strings)
**Source**: `Tag.top_tags` → `TopicList#top_tags`
**Frontend Usage**: 
- `tag-drop.js` - expects strings but has fallback for objects (line 181-186)
- `build-topic-route.js` - sets `Site.top_tags` and `Site.category_top_tags`
- `tags-section.gjs` - uses `site.navigation_menu_site_top_tags` (already objects via `serialize_tags`)

**Status**: ✅ **TARGET OF THIS CHANGE** - Change to `[{id: 12, name: "sushi"}, {id: 14, name: "coriander"}]`

---

### 2. Topic Tags (`TopicTagsMixin#tags`)
**Location**: `TopicTagsMixin` (used by `TopicListItemSerializer`, `TopicSerializer`, etc.)
**Current Format**: `["sushi", "coriander"]` (array of strings)
**Source**: `all_tags.map(&:name)` (line 16)
**Frontend Usage**:
- `render-tags.js` - expects strings (line 82-89, uses `tag` as string directly)
- `render-tag.js` - expects string (line 18: `escapeExpression(tag)`)
- `topic-list/item.gjs` - expects strings (line 63: `tags?.map((tagName) => ...)`)
- `latest-topic-list-item.gjs` - expects strings (line 21: `tags?.map((tagName) => ...)`)
- `topic-tracking-state.js` - expects strings (line 607: `topic.tags?.includes(tagId)`)
- `tag-list.gjs` - **EXPECTS OBJECTS** (line 62: `tag.name`) - **INCONSISTENCY!**

**Status**: ⚠️ **INCONSISTENT** - Most code expects strings, but `tag-list.gjs` expects objects. This suggests a mixed state.

---

### 3. `TopicListSerializer#tags` (has_many)
**Location**: `TopicListSerializer` (line 15)
**Current Format**: Array of `TagSerializer` objects (via `has_many :tags`)
**Source**: `TopicList#tags` (Tag objects from `@opts[:tag_ids]`)
**Frontend Usage**: Unknown - need to check

**Status**: ✅ **ALREADY OBJECTS** - Uses `TagSerializer` which returns `{id, name, topic_count, ...}`

---

### 4. `SiteCategorySerializer#allowed_tags`
**Location**: `SiteCategorySerializer` (line 20-22)
**Current Format**: `["sushi", "coriander"]` (array of strings)
**Source**: `object.tags.pluck(:name)`
**Frontend Usage**: Unknown - likely used in category settings/admin

**Status**: ❓ **UNKNOWN USAGE** - May need objects if frontend requires tag IDs

---

### 5. `SiteCategorySerializer#allowed_tag_groups`
**Location**: `SiteCategorySerializer` (line 28-30)
**Current Format**: `["group1", "group2"]` (array of strings - tag group names, not tags)
**Source**: `object.tag_groups.pluck(:name)`
**Status**: ℹ️ **TAG GROUPS, NOT TAGS** - Out of scope

---

### 6. `TagGroupSerializer#tag_names`
**Location**: `TagGroupSerializer` (line 6-8)
**Current Format**: `["sushi", "coriander"]` (array of strings)
**Source**: `object.tags.base_tags.map(&:name).sort`
**Frontend Usage**: `tag-info.gjs` - uses `tagGroupNames` as strings (line 45-50)

**Status**: ❓ **UNKNOWN IF NEEDS CHANGE** - Used in admin/tag info display

---

### 7. `EmbeddableHostSerializer#tags`
**Location**: `EmbeddableHostSerializer` (line 14-16)
**Current Format**: `["sushi", "coriander"]` (array of strings)
**Source**: `object.tags.map(&:name)`
**Frontend Usage**: Unknown - likely admin only

**Status**: ❓ **UNKNOWN USAGE** - Admin feature, may not need change

---

### 8. `ReviewableSerializer#tags`
**Location**: `ReviewableSerializer` (line 110)
**Current Format**: `["sushi", "coriander"]` (array of strings)
**Source**: `object.topic.tags.map(&:name)`
**Frontend Usage**: `reviewable-tags.gjs` - passes to `discourseTags` helper which expects strings

**Status**: ⚠️ **USES TOPIC TAGS** - Same as #2, inherits TopicTagsMixin behavior

---

### 9. `GroupedSearchResultSerializer#tags` (has_many)
**Location**: `GroupedSearchResultSerializer` (line 7)
**Current Format**: Array of `TagSerializer` objects
**Source**: `has_many :tags, serializer: TagSerializer`
**Status**: ✅ **ALREADY OBJECTS**

---

### 10. `AdminWebHookSerializer#tags` (has_many)
**Location**: `AdminWebHookSerializer` (line 14)
**Current Format**: Array of `TagSerializer` objects
**Source**: `has_many :tags, serializer: TagSerializer`
**Status**: ✅ **ALREADY OBJECTS**

---

### 11. `DetailedTagSerializer#synonyms`
**Location**: `DetailedTagSerializer` (line 8-10)
**Current Format**: Array of objects (via `TagsController.tag_counts_json`)
**Source**: `TagsController.tag_counts_json(object.synonyms, scope)`
**Status**: ✅ **ALREADY OBJECTS**

---

### 12. `DetailedTagSerializer#tag_group_names`
**Location**: `DetailedTagSerializer` (line 24-26)
**Current Format**: `["group1", "group2"]` (array of strings - tag group names)
**Source**: `object.tag_groups.map(&:name)`
**Status**: ℹ️ **TAG GROUPS, NOT TAGS** - Out of scope

---

## Frontend Component Analysis

### Components Expecting Strings:
1. `render-tags.js` - Core rendering, expects strings
2. `render-tag.js` - Core rendering, expects strings  
3. `topic-list/item.gjs` - Uses `tags?.map((tagName) => ...)`
4. `latest-topic-list-item.gjs` - Uses `tags?.map((tagName) => ...)`
5. `topic-tracking-state.js` - Uses `topic.tags?.includes(tagId)`
6. `reviewable-tags.gjs` - Passes to `discourseTags` (expects strings)

### Components Expecting Objects:
1. `tag-list.gjs` - Uses `tag.name` (line 62) - **INCONSISTENCY!**
2. `tag-drop.js` - Has fallback for both (line 181-186)

### Components Using `top_tags`:
1. `tag-drop.js` - Uses `site.top_tags` and `site.category_top_tags`
2. `tags-section.gjs` - Uses `site.navigation_menu_site_top_tags` (already objects)

---

## Critical Finding: Inconsistency in Topic Tags

**Problem**: `TopicTagsMixin#tags` returns strings, but `tag-list.gjs` expects objects with `.name` property.

**Investigation Needed**: Check if `tag-list.gjs` is actually receiving objects from somewhere else, or if this is a bug.

---

## Decision Matrix

### Option A: Change ONLY `top_tags`
**Pros**:
- Minimal scope, lower risk
- `top_tags` is separate from topic tags
- Frontend `tag-drop.js` already handles both formats

**Cons**:
- Inconsistency: some tag arrays are objects, some are strings
- If frontend components evolve to require tag IDs, we'll need another migration

### Option B: Change ALL tag arrays to objects
**Pros**:
- Consistency across API
- Future-proof: frontend can always access tag IDs
- Aligns with `TagSerializer` pattern (already objects)

**Cons**:
- Much larger scope - affects many serializers
- More frontend changes needed
- Higher risk of breaking changes
- `render-tags.js` and `render-tag.js` need updates

### Option C: Change `top_tags` + `TopicTagsMixin#tags` (topic tags)
**Pros**:
- Covers the two main tag array types
- Topic tags are the most commonly used
- `tag-list.gjs` inconsistency suggests objects may be expected

**Cons**:
- Still leaves other tag arrays as strings
- Requires updating `render-tags.js` and `render-tag.js`

---

## Recommendation

**Start with Option A (only `top_tags`)**, but **investigate the `tag-list.gjs` inconsistency first**.

If `tag-list.gjs` is actually receiving objects (perhaps from a different source), then we should consider Option C (change `top_tags` + `TopicTagsMixin#tags`).

The key question: **Do frontend components need tag IDs, or just names?**
- If they only need names: Option A is sufficient
- If they need IDs (for linking, filtering, etc.): Option C or B is needed

