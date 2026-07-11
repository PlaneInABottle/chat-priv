# frozen_string_literal: true

class AssistantReleases::Snapshot
  def self.fingerprint(snapshot)
    Digest::SHA256.hexdigest(JSON.generate(canonicalize(snapshot.deep_stringify_keys)))
  end

  def self.canonicalize(value)
    case value
    when Hash
      value.keys.sort.index_with { |key| canonicalize(value[key]) }
    when Array
      value.map { |item| canonicalize(item) }
    else
      value
    end
  end

  private_class_method :canonicalize
end
