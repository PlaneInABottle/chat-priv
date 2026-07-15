const path = require('node:path');

const root = __dirname;
const runner = path.join(root, 'scripts/server/run-role.sh');

module.exports = {
  apps: [
    {
      name: 'kozmopath-web',
      cwd: root,
      script: runner,
      args: ['web'],
      interpreter: 'none',
      autorestart: true,
      min_uptime: '10s',
      max_restarts: 10,
      restart_delay: 5000,
      max_memory_restart: '2500M',
      kill_timeout: 30000,
      time: true,
      env: { PORT: '3000' },
    },
    {
      name: 'kozmopath-worker',
      cwd: root,
      script: runner,
      args: ['worker'],
      interpreter: 'none',
      autorestart: true,
      min_uptime: '10s',
      max_restarts: 10,
      restart_delay: 5000,
      max_memory_restart: '2500M',
      kill_timeout: 300000,
      time: true,
    },
    {
      name: 'kozmopath-voice',
      cwd: root,
      script: runner,
      args: ['voice'],
      interpreter: 'none',
      autorestart: true,
      min_uptime: '10s',
      max_restarts: 10,
      restart_delay: 5000,
      max_memory_restart: '1500M',
      kill_timeout: 320000,
      time: true,
    },
  ],
};
