#!/usr/bin/env node

const fs = require('fs');
const path = require('path');

const GREEN = '\x1b[32m';
const YELLOW = '\x1b[33m';
const CYAN = '\x1b[36m';
const RED = '\x1b[31m';
const NC = '\x1b[0m';

const packageRoot = path.resolve(__dirname, '..');
const targetDir = process.cwd();

console.log(`${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}`);
console.log(`${CYAN}  Agent Council - Installation${NC}`);
console.log(`${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}`);
console.log();

function copyRecursive(src, dest) {
  const stat = fs.statSync(src);

  if (stat.isDirectory()) {
    if (!fs.existsSync(dest)) {
      fs.mkdirSync(dest, { recursive: true });
    }
    const files = fs.readdirSync(src);
    for (const file of files) {
      copyRecursive(path.join(src, file), path.join(dest, file));
    }
  } else {
    fs.copyFileSync(src, dest);
    // Preserve executable permission for .sh files
    if (src.endsWith('.sh')) {
      fs.chmodSync(dest, 0o755);
    }
  }
}

try {
  // Copy skills folder
  const skillsSrc = path.join(packageRoot, 'skills');
  const skillsDest = path.join(targetDir, 'skills');

  if (fs.existsSync(skillsSrc)) {
    console.log(`${YELLOW}Installing skills...${NC}`);
    copyRecursive(skillsSrc, skillsDest);
    console.log(`${GREEN}  ✓ skills/agent-council${NC}`);
  }

  // Copy config file if not exists
  const configSrc = path.join(packageRoot, 'council.config.yaml');
  const configDest = path.join(targetDir, 'council.config.yaml');

  if (fs.existsSync(configSrc) && !fs.existsSync(configDest)) {
    console.log(`${YELLOW}Installing config...${NC}`);
    fs.copyFileSync(configSrc, configDest);
    console.log(`${GREEN}  ✓ council.config.yaml${NC}`);
  } else if (fs.existsSync(configDest)) {
    console.log(`${YELLOW}  ⓘ council.config.yaml already exists, skipping${NC}`);
  }

  console.log();
  console.log(`${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}`);
  console.log(`${GREEN}  Installation complete!${NC}`);
  console.log(`${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}`);
  console.log();
  console.log(`${CYAN}Usage in Claude:${NC}`);
  console.log(`  "Summon the council"`);
  console.log(`  "Let's hear opinions from other AIs"`);
  console.log();
  console.log(`${CYAN}Direct execution:${NC}`);
  console.log(`  ./skills/agent-council/scripts/council.sh "your question"`);
  console.log();
  console.log(`${YELLOW}Note: Make sure codex and gemini CLIs are installed.${NC}`);

} catch (error) {
  console.error(`${RED}Error during installation: ${error.message}${NC}`);
  process.exit(1);
}
