# frozen_string_literal: true

# name: discourse-search-thumbnails
# about: Shows thumbnail previews of images in quick search results when using the with:images filter
# meta_topic_id: 395082
# version: 0.1.0
# authors: Canapin & AI
# url: https://github.com/discourse/discourse-search-thumbnails
# required_version: 2.7.0

enabled_site_setting :search_thumbnails_enabled

register_asset "stylesheets/search-thumbnails.scss"

after_initialize do
  rejected_img_classes = %w[emoji site-icon thumbnail avatar]

  extract_image_urls = ->(cooked) do
    cooked
      .scan(/<img[^>]*>/)
      .reject do |tag|
        tag[/class="([^"]*)"/, 1]&.split&.any? { |c| rejected_img_classes.include?(c) }
      end
      .filter_map { |tag| tag[/src="([^"]+)"/, 1] }
  end

  add_to_serializer(
    :search_post,
    :image_search_data,
    include_condition: -> do
      return false if object.image_upload_id.blank?
      return true unless SiteSetting.search_thumbnails_only_with_images_filter
      options[:result]&.term&.match?(/with:images/i)
    end,
  ) do
    urls = extract_image_urls.call(object.cooked)
    max_count = SiteSetting.search_thumbnails_max_count
    limited_urls = max_count.zero? ? urls : urls.first(max_count)
    { urls: limited_urls, total: urls.size }
  end
end
