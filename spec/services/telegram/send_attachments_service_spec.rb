require 'rails_helper'
require 'tempfile'

RSpec.describe Telegram::SendAttachmentsService do
  describe '#perform' do
    let(:channel) { create(:channel_telegram) }
    let(:message) { build(:message, conversation: create(:conversation, inbox: channel.inbox)) }
    let(:service) { described_class.new(message: message) }
    let(:telegram_api_url) { channel.telegram_api_url }

    before do
      allow(channel).to receive(:chat_id).and_return('chat123')

      stub_request(:post, "#{telegram_api_url}/sendMediaGroup")
        .to_return(status: 200, body: { ok: true, result: [{ message_id: 'media' }] }.to_json, headers: { 'Content-Type' => 'application/json' })

      stub_request(:post, "#{telegram_api_url}/sendDocument")
        .to_return(status: 200, body: { ok: true, result: { message_id: 'document' } }.to_json, headers: { 'Content-Type' => 'application/json' })
    end

    it 'sends all types of attachments in seperate groups and returns the last successful message ID from the batch' do
      attach_files(message)
      result = service.perform
      expect(result).to eq('document')
      # videos and images are sent in a media group
      # audio is sent in another group
      expect(a_request(:post, "#{telegram_api_url}/sendMediaGroup")).to have_been_made.times(2)
      expect(a_request(:post, "#{telegram_api_url}/sendDocument")).to have_been_made.once
    end

    context 'when all attachments are documents' do
      before do
        2.times { attach_file_to_message(message, 'file', 'sample.pdf', 'application/pdf') }
        message.save!
      end

      it 'sends documents individually and returns the message ID of the first successful document' do
        result = service.perform
        expect(result).to eq('document')
        expect(a_request(:post, "#{telegram_api_url}/sendDocument")).to have_been_made.times(2)
      end
    end

    context 'when a document filename includes non-ASCII characters' do
      let(:turkish_filename) { 'Sineklik_Montaj_Talimatı.pdf' }

      before do
        attach_file_to_message(message, 'file', 'sample.pdf', 'application/pdf', attached_filename: turkish_filename)
        message.save!
      end

      it 'sends the document with the original filename' do
        result = service.perform
        expect(result).to eq('document')
        expect(a_request(:post, "#{telegram_api_url}/sendDocument")
          .with { |req|
            body = req.body.force_encoding('UTF-8')
            body.include?(%Q(filename="#{turkish_filename}"))
          }).to have_been_made.once
      end
    end

    context 'when a document filename has invalid encoding' do
      let(:invalid_filename) { "bad\xC3\x28name.pdf".force_encoding('UTF-8') }
      let(:sanitized_filename) { invalid_filename.encode('UTF-8', invalid: :replace, undef: :replace, replace: '_') }

      before do
        @invalid_attachment = attach_file_to_message(message, 'file', 'sample.pdf', 'application/pdf')
        message.save!
        allow(@invalid_attachment.file.blob).to receive(:filename).and_return(invalid_filename)
      end

      it 'replaces invalid bytes with underscores and does not crash' do
        expect(sanitized_filename).to include('_')
        result = service.perform
        expect(result).to eq('document')
        expect(a_request(:post, "#{telegram_api_url}/sendDocument")
          .with { |req|
            body = req.body.force_encoding('UTF-8')
            body.include?(%Q(filename="#{sanitized_filename}"))
          }).to have_been_made.once
      end
    end

    context 'when a document attachment is missing its blob' do
      before do
        message.attachments.new(account_id: message.account_id, file_type: 'file')
        message.save!
      end

      it 'logs an error and returns nil' do
        expect(Rails.logger).to receive(:error) do |*args, &block|
          expect(args).to be_empty
          expect(block.call).to include('Attachment blob missing')
        end

        result = service.perform

        expect(result).to be_nil
        expect(a_request(:post, "#{telegram_api_url}/sendDocument")).not_to have_been_made
      end
    end

    context 'when multiple documents have mixed filename encodings' do
      let(:turkish_filename) { 'Sineklik_Montaj_Talimatı.pdf' }
      let(:invalid_filename) { "bad\xC3\x28name.pdf".force_encoding('UTF-8') }
      let(:sanitized_filename) { invalid_filename.encode('UTF-8', invalid: :replace, undef: :replace, replace: '_') }

      before do
        attach_file_to_message(message, 'file', 'sample.pdf', 'application/pdf', attached_filename: turkish_filename)
        @invalid_attachment = attach_file_to_message(message, 'file', 'sample.pdf', 'application/pdf')
        message.save!
        allow(@invalid_attachment.file.blob).to receive(:filename).and_return(invalid_filename)
      end

      it 'sends each document with sanitized filenames' do
        result = service.perform

        expect(result).to eq('document')
        expect(a_request(:post, "#{telegram_api_url}/sendDocument")).to have_been_made.times(2)
        expect(a_request(:post, "#{telegram_api_url}/sendDocument")
          .with { |req|
            body = req.body.force_encoding('UTF-8')
            body.include?(%Q(filename="#{turkish_filename}"))
          }).to have_been_made
        expect(a_request(:post, "#{telegram_api_url}/sendDocument")
          .with { |req|
            body = req.body.force_encoding('UTF-8')
            body.include?(%Q(filename="#{sanitized_filename}"))
          }).to have_been_made
      end
    end

    context 'when this is business chat' do
      before { allow(channel).to receive(:business_connection_id).and_return('eooW3KF5WB5HxTD7T826') }

      it 'sends all types of attachments in seperate groups and returns the last successful message ID from the batch' do
        attach_files(message)
        service.perform
        expect(a_request(:post, "#{telegram_api_url}/sendMediaGroup")
          .with { |req| req.body =~ /business_connection_id.+eooW3KF5WB5HxTD7T826/m })
          .to have_been_made.times(2)

        expect(a_request(:post, "#{telegram_api_url}/sendDocument")
          .with { |req| req.body =~ /business_connection_id.+eooW3KF5WB5HxTD7T826/m })
          .to have_been_made.once
      end
    end

    context 'when all attachments are photo and video' do
      before do
        2.times { attach_file_to_message(message, 'image', 'sample.png', 'image/png') }
        attach_file_to_message(message, 'video', 'sample.mp4', 'video/mp4')
        message.save!
      end

      it 'sends in a single media group and returns the message ID' do
        result = service.perform
        expect(result).to eq('media')
        expect(a_request(:post, "#{telegram_api_url}/sendMediaGroup")).to have_been_made.once
      end
    end

    context 'when all attachments are audio' do
      before do
        2.times { attach_file_to_message(message, 'audio', 'sample.mp3', 'audio/mpeg') }
        message.save!
      end

      it 'sends audio messages in single media group and returns the message ID' do
        result = service.perform
        expect(result).to eq('media')
        expect(a_request(:post, "#{telegram_api_url}/sendMediaGroup")).to have_been_made.once
      end
    end

    context 'when all attachments are photos, videos, and audio' do
      before do
        attach_file_to_message(message, 'image', 'sample.png', 'image/png')
        attach_file_to_message(message, 'video', 'sample.mp4', 'video/mp4')
        attach_file_to_message(message, 'audio', 'sample.mp3', 'audio/mpeg')
        message.save!
      end

      it 'sends photos and videos in a media group and audio in a separate group' do
        result = service.perform
        expect(result).to eq('media')
        expect(a_request(:post, "#{telegram_api_url}/sendMediaGroup")).to have_been_made.times(2)
      end
    end

    context 'when an attachment fails to send' do
      before do
        stub_request(:post, "#{telegram_api_url}/sendDocument")
          .to_return(status: 500, body: { ok: false,
                                          description: 'Internal server error' }.to_json, headers: { 'Content-Type' => 'application/json' })
      end

      it 'logs an error, stops processing, and returns nil' do
        attach_files(message)
        expect(Rails.logger).to receive(:error).at_least(:once)
        result = service.perform
        expect(result).to be_nil
        expect(a_request(:post, "#{telegram_api_url}/sendDocument")).to have_been_made.once
      end
    end

    def attach_files(message)
      attach_file_to_message(message, 'file', 'sample.pdf', 'application/pdf')
      attach_file_to_message(message, 'image', 'sample.png', 'image/png')
      attach_file_to_message(message, 'video', 'sample.mp4', 'video/mp4')
      attach_file_to_message(message, 'audio', 'sample.mp3', 'audio/mpeg')
      message.save!
    end

    def attach_file_to_message(message, type, filename, content_type, attached_filename: filename)
      attachment = message.attachments.new(account_id: message.account_id, file_type: type)
      attachment.file.attach(io: Rails.root.join("spec/assets/#{filename}").open, filename: attached_filename, content_type: content_type)
      attachment
    end
  end

  describe Telegram::SendAttachmentsService::FileWithName do
    let(:tempfile) { Tempfile.new('telegram-upload') }

    after { tempfile.close! }

    it 'exposes filename, content type, and delegates to the file' do
      tempfile.write('payload')
      tempfile.rewind

      wrapper = described_class.new(tempfile, filename: 'note.txt', content_type: 'text/plain')

      expect(wrapper.original_filename).to eq('note.txt')
      expect(wrapper.content_type).to eq('text/plain')
      expect(wrapper.read).to eq('payload')

      wrapper.rewind

      expect(wrapper.read).to eq('payload')
      expect(wrapper.path).to eq(tempfile.path)
    end

    context 'when reading binary data' do
      it 'force encodes binary data with UTF-8 encoding tag' do
        # Simulate binary PDF/PNG content that would typically have BINARY encoding
        binary_content = "\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR".b
        tempfile.binmode
        tempfile.write(binary_content)
        tempfile.rewind

        wrapper = described_class.new(tempfile, filename: 'image.png', content_type: 'image/png')
        result = wrapper.read

        # Verify bytes are preserved
        expect(result.bytes).to eq(binary_content.bytes)
        # Verify encoding is UTF-8 (matching HTTParty's multipart buffer encoding)
        expect(result.encoding).to eq(Encoding::UTF_8)
      end

      it 'handles non-ASCII filename with binary content without encoding error' do
        # Simulate the exact error scenario: Turkish/non-ASCII filename + binary PDF
        turkish_filename = 'Sineklik_Montaj_Talimatı.pdf'
        pdf_path = Rails.root.join('spec/assets/sample.pdf')
        binary_content = File.binread(pdf_path)

        tempfile.binmode
        tempfile.write(binary_content)
        tempfile.rewind

        wrapper = described_class.new(tempfile, filename: turkish_filename, content_type: 'application/pdf')

        # Verify no encoding error is raised when reading
        expect { wrapper.read }.not_to raise_error

        wrapper.rewind
        result = wrapper.read

        # Verify bytes are intact
        expect(result.bytes).to eq(binary_content.bytes)
        # Verify encoding is UTF-8
        expect(result.encoding).to eq(Encoding::UTF_8)
      end

      it 'handles empty file returning empty string' do
        # Empty tempfile - do not write anything
        tempfile.rewind

        wrapper = described_class.new(tempfile, filename: 'empty.txt', content_type: 'text/plain')
        result = wrapper.read

        # Assert returns empty string, not nil
        expect(result).to eq('')
        expect(result).not_to be_nil
      end

      it 'applies UTF-8 encoding to partial reads with read(n)' do
        binary_content = "\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x10".b
        tempfile.binmode
        tempfile.write(binary_content)
        tempfile.rewind

        wrapper = described_class.new(tempfile, filename: 'image.png', content_type: 'image/png')

        # Partial read
        result = wrapper.read(10)

        # Verify encoding is UTF-8
        expect(result.encoding).to eq(Encoding::UTF_8)
        # Verify bytes match the first 10 bytes
        expect(result.bytes).to eq(binary_content.bytes[0, 10])
      end
    end
  end
end
