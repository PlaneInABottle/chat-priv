class Voice::Recordings::StopService
  TERMINAL_EGRESS_STATUSES = %w[EGRESS_COMPLETE EGRESS_FAILED EGRESS_ABORTED EGRESS_LIMIT_REACHED].freeze
  FAILED_TERMINAL_EGRESS_STATUSES = (TERMINAL_EGRESS_STATUSES - ['EGRESS_COMPLETE']).freeze
  STOP_RECONCILE_ATTEMPTS = 5
  STOP_RECONCILE_INTERVAL_SECONDS = 1

  def self.perform(call:)
    new(call: call).perform
  end

  def initialize(call:)
    @call = call
  end

  def perform
    recording = VoiceRecording.where(call_id: call.id).active.latest_first.first
    return { 'status' => 'skipped', 'reason' => 'no_active_recording' } unless recording&.egress_id

    result = Voice::Livekit::EgressService.stop(egress_id: recording.egress_id, call: call)
    recording.update!(metadata: (recording.metadata || {}).merge('stop_result' => result))
    result = reconcile_egress(recording, result)
    finalize_from_stop_response(result)
    finalize_not_found_stop_failure(recording, result)
    result
  end

  private

  attr_reader :call

  def reconcile_egress(recording, result)
    return reconcile_terminal_stop_failure(recording, result) if already_terminal_stop_failure?(result)
    return reconcile_pending_stop(recording, result) if pending_stop_result?(result)

    result
  end

  def reconcile_terminal_stop_failure(recording, result)
    lookup_result = Voice::Livekit::EgressService.fetch(egress_id: recording.egress_id, call: call)
    recording.update!(
      metadata: (recording.metadata || {}).merge('stop_reconcile_result' => lookup_result)
    )
    return lookup_result if lookup_result['status'] == 'ok'

    finalize_failed_terminal_stop(recording, result)
    result.merge('reconcile_result' => lookup_result)
  end

  def reconcile_pending_stop(recording, result)
    lookup_result = result
    STOP_RECONCILE_ATTEMPTS.times do |attempt|
      lookup_result = Voice::Livekit::EgressService.fetch(egress_id: recording.egress_id, call: call)
      recording.update!(
        metadata: (recording.metadata || {}).merge('stop_reconcile_result' => lookup_result)
      )
      return lookup_result if terminal_egress_status?(lookup_result.dig('response', 'status'))

      sleep STOP_RECONCILE_INTERVAL_SECONDS if attempt < STOP_RECONCILE_ATTEMPTS - 1
    end

    result.merge('reconcile_result' => lookup_result)
  end

  def finalize_from_stop_response(result)
    response = result['response']
    return unless result['status'] == 'ok' && response.is_a?(Hash)
    return unless terminal_egress_status?(response['status'])

    Voice::Recordings::WebhookHandler.perform!(
      payload: {
        'event' => 'egress_ended',
        'egressInfo' => response
      }
    )
  end

  def finalize_failed_terminal_stop(recording, result)
    egress_status = terminal_status_from_error(result['error'])
    return unless FAILED_TERMINAL_EGRESS_STATUSES.include?(egress_status)

    finalize_failed_recording(recording, egress_status, result['error'])
  end

  def finalize_not_found_stop_failure(recording, result)
    return unless egress_not_found_stop_failure?(result)

    finalize_failed_recording(recording, 'EGRESS_FAILED', result['error'])
  end

  def finalize_failed_recording(recording, egress_status, error)
    Voice::Recordings::WebhookHandler.perform!(
      payload: {
        'event' => 'egress_ended',
        'egressInfo' => {
          'egress_id' => recording.egress_id,
          'status' => egress_status,
          'error' => error,
          'ended_at' => (Time.zone.now.to_f * 1_000_000_000).to_i
        }
      }
    )
  end

  def already_terminal_stop_failure?(result)
    result['status'] == 'failed' &&
      result['code'].to_s == '412' &&
      terminal_status_from_error(result['error']).present?
  end

  def pending_stop_result?(result)
    result['status'] == 'ok' &&
      result['response'].is_a?(Hash) &&
      !terminal_egress_status?(result['response']['status'])
  end

  def terminal_status_from_error(error)
    TERMINAL_EGRESS_STATUSES.find { |status| error.to_s.include?(status) }
  end

  def terminal_egress_status?(status)
    status.to_s.in?(TERMINAL_EGRESS_STATUSES + %w[3 4 5 6])
  end

  def egress_not_found_stop_failure?(result)
    result['status'] == 'failed' &&
      result['code'].to_s == '404' &&
      result['error'].to_s.match?(/egress|object/i)
  end
end
