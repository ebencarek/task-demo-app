# Local Development Setup

## Prerequisites

- **Node.js 18+** - [Download here](https://nodejs.org/)
- **PostgreSQL** - [Download here](https://www.postgresql.org/download/)
- **Git** - [Download here](https://git-scm.com/)

## Quick Start

### 1. Database Setup

First, set up a local PostgreSQL database:

```bash
# Create database (assumes you have PostgreSQL running)
createdb customerdb

# Initialize with test data
psql -U postgres -d customerdb -f init.sql
```

**Alternative with Docker:**
```bash
# Run PostgreSQL in Docker
docker run --name postgres-local -e POSTGRES_PASSWORD=postgres123 -e POSTGRES_DB=customerdb -p 5432:5432 -d postgres:15

# Wait for container to start, then initialize
docker exec -i postgres-local psql -U postgres -d customerdb < init.sql
```

### 2. Backend API Setup

```bash
# Navigate to backend directory
cd backend

# Install dependencies
npm install

# Set environment variables (optional - has defaults)
export DB_HOST=localhost
export DB_USER=postgres
export DB_PASSWORD=postgres123
export DB_NAME=customerdb
export DB_PORT=5432

# Start the backend server
npm start
```

Backend will run on: **http://localhost:3001**

Test endpoints:
- Health check: http://localhost:3001/health
- Customer data: http://localhost:3001/api/customers

### 3. Frontend Setup

Open a new terminal:

```bash
# Navigate to frontend directory
cd frontend

# Install dependencies
npm install

# Start the development server
npm start
```

Frontend will run on: **http://localhost:3000**

The React app will automatically proxy API requests to the backend on port 3001.

## Development Workflow

### Backend Development
- Backend runs on port **3001**
- Edit `backend/server.js` for API changes
- Server auto-restarts with nodemon (if installed): `npm install -g nodemon && nodemon server.js`

### Frontend Development
- Frontend runs on port **3000** with hot reload
- Edit `frontend/src/App.js` for React components
- Edit `frontend/src/App.css` for styling
- Changes appear instantly in browser

### Database Queries
The app includes an intentionally slow query to demonstrate performance issues:
- Click "📊 Analyze Customer Data"
- Query will take 10-30+ seconds due to missing indexes
- This simulates real-world performance problems

## Troubleshooting

### Backend Issues
```bash
# Check if PostgreSQL is running
brew services list | grep postgres  # macOS
sudo systemctl status postgresql    # Linux
# Windows: Check Services.msc

# Test database connection
psql -U postgres -h localhost -d customerdb -c "SELECT version();"

# Check backend logs
cd backend && npm start
```

### Frontend Issues
```bash
# Clear npm cache
npm cache clean --force

# Reinstall dependencies
rm -rf node_modules package-lock.json
npm install

# Check if backend is running
curl http://localhost:3001/health
```

### Environment Variables
Create `.env` files if needed:

**backend/.env:**
```
DB_HOST=localhost
DB_USER=postgres
DB_PASSWORD=postgres123
DB_NAME=customerdb
DB_PORT=5432
PORT=3001
```

**frontend/.env:**
```
REACT_APP_API_URL=http://localhost:3001
```

## Docker Development (Alternative)

### Build and run with Docker:

```bash
# Backend
cd backend
docker build -t customer-backend .
docker run -p 3001:3001 -e DB_HOST=host.docker.internal customer-backend

# Frontend
cd frontend
docker build -t customer-frontend .
docker run -p 3000:80 -e REACT_APP_API_URL=http://localhost:3001 customer-frontend
```

### Using Docker Compose:

Create `docker-compose.yml` in root:
```yaml
version: '3.8'
services:
  postgres:
    image: postgres:15
    environment:
      POSTGRES_DB: customerdb
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres123
    ports:
      - "5432:5432"
    volumes:
      - ./init.sql:/docker-entrypoint-initdb.d/init.sql

  backend:
    build: ./backend
    ports:
      - "3001:3001"
    environment:
      DB_HOST: postgres
      DB_USER: postgres
      DB_PASSWORD: postgres123
      DB_NAME: customerdb
    depends_on:
      - postgres

  frontend:
    build: ./frontend
    ports:
      - "3000:80"
    environment:
      REACT_APP_API_URL: http://localhost:3001
    depends_on:
      - backend
```

Run with: `docker-compose up`

## What You Should See

1. **Frontend Dashboard**: Modern purple gradient dashboard at http://localhost:3000
2. **System Health Card**: Shows API status (should be green/ONLINE)
3. **Interactive Buttons**:
   - "📊 Analyze Customer Data" - Triggers slow query
   - "🔄 Refresh Dashboard" - Updates health status
4. **Performance Metrics**: Shows query timing and performance badges
5. **Customer Insights**: Displays sample data after running analytics

The dashboard automatically refreshes health status every 30 seconds and provides real-time performance monitoring.