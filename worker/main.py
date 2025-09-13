from datetime import datetime
from supabase_service import SupabaseService
from models import (
    User,
    AppMarker,
    Issue,
    Event,
    MarkerType,
    IssueCategory,
    IssueStatus,
    EventCategory,
    EventStatus,
)
from uuid import uuid4


def main():
    print("Worker started with Supabase integration!")

    try:
        # Test connection by fetching users
        users = SupabaseService.get_users(limit=5)
        print(f"Found {len(users)} users in database")

        # Example: Create a sample user (if not exists)
        sample_user_id = uuid4()

        # Check if user exists
        existing_user = SupabaseService.get_user(str(sample_user_id))
        if not existing_user:
            # Create sample user
            new_user = User(
                id=sample_user_id,
                email="sample@example.com",
                username="sample_user",
                points=10,
                created_at=datetime.now(),
                updated_at=datetime.now(),
            )
            created_user = SupabaseService.create_user(new_user)
            if created_user:
                print("Created sample user")
            else:
                print("Failed to create user")
        else:
            print("Sample user already exists")

        # Example: Fetch and display some issues
        issues = SupabaseService.get_issues(limit=3)
        print(f"Found {len(issues)} issues")

        for issue in issues:
            print(
                f"- {issue.title} ({issue.category.value}) - Status: {issue.status.value}"
            )

        # Example: Fetch and display some events
        events = SupabaseService.get_events(limit=3)
        print(f"Found {len(events)} events")

        for event in events:
            print(
                f"- {event.title} ({event.category.value}) - Status: {event.status.value}"
            )

        print("Worker operations completed successfully!")

    except Exception as e:
        print(f"Error: {e}")


if __name__ == "__main__":
    main()
