results = evaluation_run.evaluation_results.sort_by(&:id)

json.id evaluation_run.id
json.status evaluation_run.status
json.total_count evaluation_run.total_count
json.passed_count evaluation_run.passed_count
json.failed_count results.count { |result| result.failed? || (result.completed? && !result.passed?) }
json.current_draft evaluation_run.current_draft?
json.started_at evaluation_run.started_at
json.completed_at evaluation_run.completed_at
json.error_message evaluation_run.error_message
json.created_at evaluation_run.created_at
json.results results do |result|
  json.id result.id
  json.evaluation_case_id result.ai_agent_evaluation_case_id
  json.status result.status
  json.name result.case_name
  json.customer_message result.customer_message
  json.success_criteria result.success_criteria
  json.assistant_response result.assistant_response
  json.passed result.passed
  json.reason result.reason
  json.tool_events result.tool_events
end
