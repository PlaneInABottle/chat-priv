# frozen_string_literal: true

namespace :ikas do
  namespace :catalog do
    desc 'Evaluate the latest completed Ikas storefront catalog snapshot for an account'
    task eval: :environment do
      require Rails.root.join('lib/integrations/ikas/catalog').to_s

      account_id = ENV.fetch('ACCOUNT_ID')
      cases_path = ENV.fetch('CASES', Rails.root.join('config/ikas_catalog_eval/generic.yml').to_s)
      format = ENV.fetch('FORMAT', IkasCatalogMvp::CatalogEvaluator::DEFAULT_FORMAT)
      limit = ENV.fetch('LIMIT', IkasCatalogMvp::QueryEngine::DEFAULT_LIMIT).to_i

      account = Account.find(account_id)
      status = Integrations::Ikas::ConnectionStatus.new(account: account).payload
      hook = status[:state] == 'connected' ? status[:hook] : nil
      snapshots = IkasCatalogSnapshot.where(account: account)
      snapshots = snapshots.where(integrations_hook: hook) if hook
      snapshot = snapshots.storefront_catalog.latest_completed.first
      abort("No completed Ikas storefront catalog snapshot found for account #{account.id}") unless snapshot
      abort("Ikas catalog SQLite file is missing for snapshot #{snapshot.id}: #{snapshot.sqlite_path}") unless snapshot.sqlite_exists?

      report = IkasCatalogMvp::CatalogEvaluator.new(sqlite_path: snapshot.sqlite_path, cases_path: cases_path, limit: limit).evaluate
      puts IkasCatalogMvp::CatalogEvaluator.render(report, format: format)
      abort('Ikas catalog evaluation failed') unless report.fetch('status') == 'passed'
    end
  end
end
