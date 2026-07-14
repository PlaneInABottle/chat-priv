module SuperAdmin::FeaturesHelper
  def self.available_features
    YAML.load(ERB.new(Rails.root.join('app/helpers/super_admin/features.yml').read).result).with_indifferent_access
  end

  def self.plan_details
    plan = ChatwootHub.pricing_plan
    quantity = ChatwootHub.pricing_plan_quantity
    helpers = ActionController::Base.helpers
    plan_name = helpers.content_tag(:span, plan, class: 'font-semibold')

    if plan == 'premium'
      agent_count = helpers.content_tag(:span, "#{quantity} agents", class: 'font-semibold')
      helpers.safe_join(['You are currently on the ', plan_name, ' plan with ', agent_count, '.'])
    else
      helpers.safe_join(['You are currently on the ', plan_name, ' edition plan.'])
    end
  end
end
