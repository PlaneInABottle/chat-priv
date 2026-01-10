# Define a method to fetch the git commit hash
def fetch_git_sha
  # Try git command first (if .git directory exists and git is available)
  if File.directory?('.git')
    begin
      sha = `git rev-parse HEAD 2>/dev/null`.to_s.strip
      return sha if sha.present?
    rescue Errno::ENOENT
      # git command not found; fall through to fallbacks
    end
  end

  # Prefer .git_sha file (created at build/deploy time)
  return File.read('.git_sha').strip if File.exist?('.git_sha')

  # Heroku runtime metadata
  return ENV.fetch('HEROKU_SLUG_COMMIT', nil) if ENV.fetch('HEROKU_SLUG_COMMIT', nil).present?

  'unknown'
end

GIT_HASH = fetch_git_sha
