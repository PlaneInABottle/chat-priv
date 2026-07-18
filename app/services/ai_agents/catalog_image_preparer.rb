# frozen_string_literal: true

require 'image_processing/mini_magick'

class AiAgents::CatalogImagePreparer
  class Error < StandardError; end
  class InvalidSource < Error; end
  class InvalidImage < Error; end

  MAX_INPUT_BYTES = 10.megabytes
  MAX_OUTPUT_BYTES = 5.megabytes
  MAX_EDGE = 1600
  MAX_INPUT_PIXELS = 40_000_000
  ALLOWED_CONTENT_TYPES = %w[image/jpeg image/png image/webp].freeze
  CDN_HOST = IkasCatalogMvp::ImageLinkBuilder::CDN_HOST
  CDN_PATH_PATTERN = %r{\A/images/[0-9a-f-]{36}/[0-9a-f-]{36}/1080/[^/]+\z}i

  PreparedImage = Struct.new(:tempfile, :filename, :content_type, keyword_init: true) do
    def uploaded_file
      ActionDispatch::Http::UploadedFile.new(tempfile: tempfile, filename: filename, type: content_type)
    end

    def close!
      tempfile&.close!
    end
  end

  def prepare(url)
    validate_source!(url)

    SafeFetch.fetch(
      url,
      max_bytes: MAX_INPUT_BYTES,
      allowed_content_type_prefixes: [],
      allowed_content_types: ALLOWED_CONTENT_TYPES
    ) do |source|
      validate_source_file!(source.tempfile)
      validate_dimensions!(source.tempfile.path)
      normalized = normalize(source.tempfile.path)
      validate_output!(normalized)
      return PreparedImage.new(tempfile: normalized, filename: "catalog-product-#{SecureRandom.hex(6)}.jpg", content_type: 'image/jpeg')
    end
  rescue SafeFetch::Error, ImageProcessing::Error, MiniMagick::Error => e
    raise InvalidImage, e.message
  end

  private

  def validate_source!(url)
    uri = URI.parse(url.to_s)
    return if trusted_source?(uri)

    raise InvalidSource, 'Catalog image source is not trusted.'
  rescue URI::InvalidURIError
    raise InvalidSource, 'Catalog image source is invalid.'
  end

  def trusted_source?(uri)
    [
      uri.is_a?(URI::HTTPS),
      uri.host.to_s.downcase == CDN_HOST,
      uri.port == 443,
      uri.userinfo.blank?,
      uri.query.blank?,
      uri.fragment.blank?,
      uri.path.match?(CDN_PATH_PATTERN)
    ].all?
  end

  def normalize(path)
    ImageProcessing::MiniMagick
      .source(path)
      .resize_to_limit(MAX_EDGE, MAX_EDGE)
      .convert('jpg')
      .saver(quality: 85, strip: true)
      .call
  end

  def validate_dimensions!(path)
    image = MiniMagick::Image.open(path)
    return if image.width.to_i * image.height.to_i <= MAX_INPUT_PIXELS

    raise InvalidImage, 'Catalog image dimensions exceed the processing limit.'
  ensure
    image&.destroy!
  end

  def validate_source_file!(file)
    file.rewind
    mime_type = Marcel::MimeType.for(file)
    file.rewind
    return if mime_type.in?(ALLOWED_CONTENT_TYPES)

    raise InvalidImage, 'Catalog image content is invalid.'
  end

  def validate_output!(file)
    file.rewind
    mime_type = Marcel::MimeType.for(file, name: 'catalog-product.jpg')
    file.rewind
    return if mime_type == 'image/jpeg' && file.size <= MAX_OUTPUT_BYTES

    file.close!
    raise InvalidImage, 'Catalog image output is invalid.'
  end
end
