from datetime import datetime
from supabase_service import SupabaseService
from models import (
    User,
    AppMarker,
    Issue,
    Event,
    IssueVote,
    EventRSVP,
    UserPointsHistory,
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

        # Example: Create a sample user through authentication (if not exists)
        sample_email = "sample@example.com"
        
        # Check if user exists by email
        existing_user = SupabaseService.get_user_by_email(sample_email)
        if not existing_user:
            # Create sample user through Supabase Auth
            auth_result = SupabaseService.signup_user(
                email=sample_email,
                password="samplepassword123",
                username="sample_user"
            )
            if auth_result:
                print("Created sample user through authentication")
                print(f"Auth user ID: {auth_result['user'].id}")
            else:
                print("Failed to create authenticated user")
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

        # Example: Test new functionality - award points to a user
        if users:
            user_id = str(users[0].id)
            success = SupabaseService.award_points(
                user_id=user_id,
                action_type="report_issue",
                points=10,
                reference_id=None
            )
            if success:
                print(f"Awarded 10 points to user {user_id}")
            
            # Check points history
            points_history = SupabaseService.get_user_points_history(user_id, limit=5)
            print(f"User has {len(points_history)} point transactions")

        # Example: Test getting votes for issues
        if issues:
            issue_id = str(issues[0].id)
            votes = SupabaseService.get_issue_votes(issue_id)
            print(f"Issue '{issues[0].title}' has {len(votes)} votes")

        # Example: Test getting RSVPs for events
        if events:
            event_id = str(events[0].id)
            rsvps = SupabaseService.get_event_rsvps(event_id)
            print(f"Event '{events[0].title}' has {len(rsvps)} RSVPs")

        print("Worker operations completed successfully!")

    except Exception as e:
        print(f"Error: {e}")


if __name__ == "__main__":
    main()
