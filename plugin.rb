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
      topic = object.topic
      return false if topic.blank?

      # Check if topic has any images (from any post)
      has_images = topic.posts.where.not(image_upload_id: nil).exists?
      return false unless has_images

      return true unless SiteSetting.search_thumbnails_only_with_images_filter
      options[:result]&.term&.match?(/with:images/i)
    end,
  ) do
    # Collect images from all posts in the topic, not just the first one
    topic = object.topic
    all_urls = []

    topic.posts.order(:post_number).each do |post|
      next if post.cooked.blank?
      urls = extract_image_urls.call(post.cooked)
      all_urls.concat(urls)
    end

    # Remove duplicates while preserving order
    all_urls.uniq!

    max_count = SiteSetting.search_thumbnails_max_count
    limited_urls = max_count.zero? ? all_urls : all_urls.first(max_count)
    { urls: limited_urls, total: all_urls.size }
  end
end
