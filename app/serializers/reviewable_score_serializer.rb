# frozen_string_literal: true

class ReviewableScoreSerializer < ApplicationSerializer

  attributes :id, :score, :agree_stats, :status, :reason, :created_at, :reviewed_at
  has_one :user, serializer: BasicUserSerializer, root: 'users'
  has_one :score_type, serializer: ReviewableScoreTypeSerializer
  has_one :reviewable_conversation, serializer: ReviewableConversationSerializer
  has_one :reviewed_by, serializer: BasicUserSerializer, root: 'users'

  def agree_stats
    {
      agreed: user.user_stat.flags_agreed,
      disagreed: user.user_stat.flags_disagreed,
      ignored: user.user_stat.flags_ignored
    }
  end

  def reason
    return unless object.reason

    link_text = I18n.t("reviewables.reasons.site_setting_links.#{object.reason}", default: nil)
    link_text = I18n.t("reviewables.reasons.regular_links.#{object.reason}", default: nil) if link_text.nil?

    if link_text
      link = build_link_for(object.reason, link_text)
      text = I18n.t("reviewables.reasons.#{object.reason}", link: link, default: nil)
    else
      text = I18n.t("reviewables.reasons.#{object.reason}", default: nil)
    end

    text
  end

  def include_reason?
    reason.present?
  end

  private

  def url_for(reason, text)
    case reason
    when 'watched_word'
      "#{Discourse.base_url}/admin/customize/watched_words"
    when 'category'
      "#{Discourse.base_url}/c/#{object.reviewable.category&.name}/edit/settings"
    else
      "#{Discourse.base_url}/admin/site_settings/category/all_results?filter=#{text}"
    end
  end

  def build_link_for(reason, text)
    return text.gsub('_', ' ') unless scope.is_staff?

    "<a href=\"#{url_for(reason, text)}\">#{text.gsub('_', ' ')}</a>"
  end
end
