#!/bin/bash
set -euo pipefail

# SessionStart hook for JOSYEL Fleet Intelligence System
# Installs dependencies for backend (Node.js) and frontend (React)
# Runs synchronously on web session startup - guarantees readiness before session starts

cd "${CLAUDE_PROJECT_DIR:-.}"

# Backend dependencies
if [ -f "backend/package.json" ]; then
  echo "Installing backend dependencies..."
  cd backend
  npm install
  cd ..
fi

# Frontend dependencies
if [ -f "frontend/package.json" ]; then
  echo "Installing frontend dependencies..."
  cd frontend
  npm install
  cd ..
fi

echo "✓ Dependencies installed successfully"
