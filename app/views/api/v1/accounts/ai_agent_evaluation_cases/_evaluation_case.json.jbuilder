json.id evaluation_case.id
json.name AiAgents::EvaluationTextSanitizer.sanitize(evaluation_case.name)
json.customer_message AiAgents::EvaluationTextSanitizer.sanitize(evaluation_case.customer_message)
json.success_criteria AiAgents::EvaluationTextSanitizer.sanitize(evaluation_case.success_criteria)
json.position evaluation_case.position
json.needs_review evaluation_case.reviewed_at.nil?
json.created_at evaluation_case.created_at
json.updated_at evaluation_case.updated_at
