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

  # Thumbnails are displayed at 60px, so a 120px optimized image covers
  # retina/HiDPI screens while staying tiny and fast to download.
  thumbnail_size = 120

  extract_image_urls = ->(cooked) do
    cooked
      .scan(/<img[^>]*>/)
      .reject do |tag|
        tag[/class="([^"]*)"/, 1]&.split&.any? { |c| rejected_img_classes.include?(c) }
      end
      .filter_map { |tag| tag[/src="([^"]+)"/, 1] }
  end

  # Convert a full-size image URL into a small, pre-generated optimized
  # thumbnail so search results load near-instantly. Falls back to the
  # original URL when no matching upload/optimized image can be resolved.
  optimize_url = ->(url) do
    upload = Upload.get_from_url(url)
    next url unless upload
    next url unless FileHelper.is_supported_image?(upload.original_filename.to_s)

    optimized = upload.get_optimized_image(thumbnail_size, thumbnail_size, {})
    next url unless optimized

    UrlHelper.cook_url(optimized.url, secure: upload.secure?)
  rescue StandardError
    url
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
    # Collect images from all posts in the topic, ordered by most recent first
    topic = object.topic
    all_urls = []

    # Get posts ordered by most recent first (highest post_number first)
    posts = topic.posts.order("post_number DESC")
    
    posts.each do |post|
      next if post.cooked.blank?
      urls = extract_image_urls.call(post.cooked)
      all_urls.concat(urls)
    end

    # Remove duplicates while preserving order (most recent images first)
    all_urls.uniq!

    max_count = SiteSetting.search_thumbnails_max_count
    limited_urls = max_count.zero? ? all_urls : all_urls.first(max_count)
    # Only optimize the URLs we actually send to the client.
    optimized_urls = limited_urls.map { |url| optimize_url.call(url) }
    { urls: optimized_urls, total: all_urls.size }
  end
end
