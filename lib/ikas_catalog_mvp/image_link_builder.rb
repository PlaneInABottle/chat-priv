# frozen_string_literal: true

require 'cgi'

class IkasCatalogMvp::ImageLinkBuilder
  CDN_HOST = 'cdn.myikas.com'
  RENDITION_SIZE = 1080
  UUID_PATTERN = /\A[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\z/i

  def initialize(merchant_id:)
    @merchant_id = merchant_id.to_s
  end

  def rows_for(item_id:, images:, scope:)
    return [] unless valid_uuid?(merchant_id)

    ordered_images(images).filter_map.with_index do |image, position|
      row_for(item_id, image, scope, position)
    end
  end

  private

  attr_reader :merchant_id

  def ordered_images(images)
    seen = {}
    Array(images)
      .reject { |image| image['isVideo'] == true }
      .sort_by { |image| [image['isMain'] == true ? 0 : 1, image['order'].to_i] }
      .select do |image|
        image_id = image['imageId'].to_s
        next false if seen[image_id]

        seen[image_id] = true
      end
  end

  def row_for(item_id, image, scope, position)
    image_id = image['imageId'].to_s
    file_name = normalized_file_name(image['fileName'])
    return unless valid_uuid?(image_id) && file_name

    {
      'item_id' => item_id,
      'image_id' => image_id,
      'file_name' => file_name,
      'canonical_url' => canonical_url(image_id, file_name),
      'is_main' => image['isMain'] == true ? 1 : 0,
      'position' => position,
      'image_scope' => scope
    }
  end

  def canonical_url(image_id, file_name)
    escaped_name = CGI.escape(file_name).gsub('+', '%20')
    "https://#{CDN_HOST}/images/#{merchant_id}/#{image_id}/#{RENDITION_SIZE}/#{escaped_name}"
  end

  def normalized_file_name(value)
    name = value.to_s.strip
    return if name.empty?

    File.extname(name).empty? ? "#{name}.webp" : name
  end

  def valid_uuid?(value)
    value.match?(UUID_PATTERN)
  end
end
