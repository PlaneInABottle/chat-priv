FactoryBot.define do
  factory :ai_agent_evaluation_result do
    evaluation_run { association :ai_agent_evaluation_run }
    evaluation_case do
      association :ai_agent_evaluation_case,
                  account: evaluation_run.account,
                  ai_agent: evaluation_run.ai_agent
    end
    status { :pending }
    case_name { evaluation_case.name }
    customer_message { evaluation_case.customer_message }
    success_criteria { evaluation_case.success_criteria }
  end
end
