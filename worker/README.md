# Worker Service

This is the Python worker service for the HackMIT 2025 environmental crowdsourcing platform. It provides backend functionality for processing environmental data, managing users, issues, events, and reports.

## Setup

1. Install dependencies using `uv`:
   ```bash
   uv sync
   ```

2. Configure environment variables:
   - Copy `.env` and update with your actual Supabase credentials:
   ```bash
   SUPABASE_URL=https://your-project.supabase.co
   SUPABASE_ANON_KEY=your-anon-key-here
   ```

## Running the Worker

```bash
uv run python main.py
```

## Project Structure

- `main.py` - Main entry point demonstrating Supabase integration
- `models.py` - Pydantic models for all database entities
- `supabase_client.py` - Supabase client configuration
- `supabase_service.py` - Service layer for database operations
- `.env` - Environment variables (add to .gitignore)
- `pyproject.toml` - Project dependencies and configuration

## Models

The worker implements the following models based on the Flutter client:

- **User** - User profiles with points system
- **AppMarker** - Geographic markers for issues and events
- **Issue** - Environmental issues with categories and credibility scoring
- **Event** - Community events with participant management
- **Report** - Environmental reports with location data
- **IssueVote** - Voting system for issue credibility
- **EventRSVP** - Event participation tracking
- **UserPointsHistory** - Points tracking for gamification

## Database Schema

The worker connects to a Supabase PostgreSQL database with the following tables:
- `users` - User profiles
- `markers` - Geographic markers
- `issues` - Environmental issues
- `events` - Community events
- `reports` - Environmental reports
- `issue_votes` - Issue credibility votes
- `event_rsvps` - Event RSVPs
- `user_points_history` - Points history

## Features

- Full Supabase integration with Python
- Pydantic models for type safety
- Service layer for database operations
- Environment-based configuration
- Support for all entity types from the Flutter client

## Development

To add new functionality:

1. Define models in `models.py`
2. Add service methods in `supabase_service.py`
3. Update `main.py` to demonstrate usage

## Dependencies

- `supabase` - Supabase Python client
- `pydantic` - Data validation and serialization
- `python-dotenv` - Environment variable management