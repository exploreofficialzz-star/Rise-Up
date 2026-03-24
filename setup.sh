#!/usr/bin/env bash
# ============================================================
# RiseUp Quick Setup Script
# ChAs Tech Group
# ============================================================

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo ""
echo -e "${BLUE}╔════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   🚀 RiseUp Setup — ChAs Tech      ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════╝${NC}"
echo ""

# ── Check prerequisites ───────────────────────────────
echo -e "${YELLOW}Checking prerequisites...${NC}"

check_cmd() {
  if command -v "$1" &> /dev/null; then
    echo -e "  ${GREEN}✅ $1 found${NC}"
  else
    echo -e "  ${RED}❌ $1 not found — please install it first${NC}"
    exit 1
  fi
}

check_cmd python3
check_cmd pip3
check_cmd flutter
check_cmd git

echo ""

# ── Backend setup ─────────────────────────────────────
echo -e "${YELLOW}Setting up backend...${NC}"
cd backend

if [ ! -f ".env" ]; then
  cp .env.example .env
  echo -e "  ${GREEN}✅ Created .env from template${NC}"
  echo -e "  ${YELLOW}⚠️  Edit backend/.env with your API keys before running!${NC}"
else
  echo -e "  ${GREEN}✅ .env already exists${NC}"
fi

echo -e "  Installing Python dependencies..."
pip3 install -r requirements.txt -q
echo -e "  ${GREEN}✅ Python packages installed${NC}"

cd ..

# ── Flutter setup ─────────────────────────────────────
echo ""
echo -e "${YELLOW}Setting up Flutter app...${NC}"
cd frontend

echo -e "  Getting Flutter packages..."
flutter pub get
echo -e "  ${GREEN}✅ Flutter packages installed${NC}"

cd ..

# ── Git hooks ─────────────────────────────────────────
echo ""
echo -e "${YELLOW}Setting up git hooks...${NC}"
cat > .git/hooks/pre-commit << 'HOOK'
#!/bin/bash
# Prevent committing .env files
if git diff --cached --name-only | grep -q "\.env$"; then
  echo "❌ .env file detected! Remove it from staging: git reset HEAD .env"
  exit 1
fi
echo "✅ Pre-commit checks passed"
HOOK
chmod +x .git/hooks/pre-commit
echo -e "  ${GREEN}✅ Git hooks configured${NC}"

# ── Summary ───────────────────────────────────────────
echo ""
echo -e "${GREEN}════════════════════════════════════${NC}"
echo -e "${GREEN}✅ Setup complete!${NC}"
echo -e "${GREEN}════════════════════════════════════${NC}"
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo ""
echo -e "  1. ${YELLOW}Edit backend/.env${NC} with your Supabase + AI keys"
echo ""
echo -e "  2. ${YELLOW}Run Supabase migration:${NC}"
echo -e "     → Open Supabase SQL Editor"
echo -e "     → Paste & run: supabase/migrations/001_initial_schema.sql"
echo ""
echo -e "  3. ${YELLOW}Start backend:${NC}"
echo -e "     cd backend && uvicorn main:app --reload"
echo -e "     API docs: http://localhost:8000/docs"
echo ""
echo -e "  4. ${YELLOW}Run Flutter app:${NC}"
echo -e "     cd frontend && flutter run \\"
echo -e "       --dart-define=API_BASE_URL=http://10.0.2.2:8000/api/v1 \\"
echo -e "       --dart-define=SUPABASE_URL=your_url \\"
echo -e "       --dart-define=SUPABASE_ANON_KEY=your_key"
echo ""
echo -e "  5. ${YELLOW}Deploy:${NC} Push to main → GitHub Actions handles everything!"
echo ""
echo -e "  See ${BLUE}SECRETS.md${NC} for GitHub Secrets setup"
echo -e "  See ${BLUE}README.md${NC} for full documentation"
echo ""
echo -e "${GREEN}🚀 Let's build wealth together! — ChAs Tech Group${NC}"
echo ""
