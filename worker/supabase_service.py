from typing import List, Optional
from supabase_client import supabase
from models import (
    User,
    AppMarker,
    Issue,
    Event,
    IssueVote,
    EventRSVP,
    UserPointsHistory,
)


class SupabaseService:
    """Service class for interacting with Supabase database"""

    # User operations
    @staticmethod
    def get_users(limit: int = 100) -> List[User]:
        try:
            response = supabase.table("users").select("*").limit(limit).execute()
            return [User(**item) for item in response.data]
        except Exception as e:
            print(f"Error fetching users: {e}")
            return []

    @staticmethod
    def get_user(user_id: str) -> Optional[User]:
        try:
            response = supabase.table("users").select("*").eq("id", user_id).execute()
            if response.data:
                return User(**response.data[0])
            return None
        except Exception as e:
            print(f"Error fetching user: {e}")
            return None

    @staticmethod
    def create_user(user: User) -> Optional[User]:
        try:
            data = user.dict(exclude_unset=True)
            data["id"] = str(data["id"])  # Convert UUID to string
            # Convert datetime objects to ISO format strings
            if "created_at" in data and hasattr(data["created_at"], "isoformat"):
                data["created_at"] = data["created_at"].isoformat()
            if "updated_at" in data and hasattr(data["updated_at"], "isoformat"):
                data["updated_at"] = data["updated_at"].isoformat()
            response = supabase.table("users").insert(data).execute()
            if response.data:
                return User(**response.data[0])
            return None
        except Exception as e:
            print(f"Error creating user: {e}")
            return None

    # Marker operations
    @staticmethod
    def get_markers(limit: int = 100) -> List[AppMarker]:
        try:
            response = supabase.table("markers").select("*").limit(limit).execute()
            return [AppMarker(**item) for item in response.data]
        except Exception as e:
            print(f"Error fetching markers: {e}")
            return []

    @staticmethod
    def create_marker(marker: AppMarker) -> Optional[AppMarker]:
        try:
            data = marker.dict(exclude_unset=True)
            data["id"] = str(data["id"])  # Convert UUID to string
            data["created_by"] = str(data["created_by"])  # Convert UUID to string
            # Convert datetime objects to ISO format strings
            if "created_at" in data and hasattr(data["created_at"], "isoformat"):
                data["created_at"] = data["created_at"].isoformat()
            if "updated_at" in data and hasattr(data["updated_at"], "isoformat"):
                data["updated_at"] = data["updated_at"].isoformat()
            response = supabase.table("markers").insert(data).execute()
            if response.data:
                return AppMarker(**response.data[0])
            return None
        except Exception as e:
            print(f"Error creating marker: {e}")
            return None

    # Issue operations
    @staticmethod
    def get_issues(limit: int = 100) -> List[Issue]:
        try:
            response = supabase.table("issues").select("*").limit(limit).execute()
            return [Issue(**item) for item in response.data]
        except Exception as e:
            print(f"Error fetching issues: {e}")
            return []

    @staticmethod
    def create_issue(issue: Issue) -> Optional[Issue]:
        try:
            data = issue.dict(exclude_unset=True)
            data["id"] = str(data["id"])  # Convert UUID to string
            data["marker_id"] = str(data["marker_id"])  # Convert UUID to string
            # Convert datetime objects to ISO format strings
            if "created_at" in data and hasattr(data["created_at"], "isoformat"):
                data["created_at"] = data["created_at"].isoformat()
            if "updated_at" in data and hasattr(data["updated_at"], "isoformat"):
                data["updated_at"] = data["updated_at"].isoformat()
            response = supabase.table("issues").insert(data).execute()
            if response.data:
                return Issue(**response.data[0])
            return None
        except Exception as e:
            print(f"Error creating issue: {e}")
            return None

    # Event operations
    @staticmethod
    def get_events(limit: int = 100) -> List[Event]:
        try:
            response = supabase.table("events").select("*").limit(limit).execute()
            return [Event(**item) for item in response.data]
        except Exception as e:
            print(f"Error fetching events: {e}")
            return []

    @staticmethod
    def create_event(event: Event) -> Optional[Event]:
        try:
            data = event.dict(exclude_unset=True)
            data["id"] = str(data["id"])  # Convert UUID to string
            data["marker_id"] = str(data["marker_id"])  # Convert UUID to string
            # Convert datetime objects to ISO format strings
            if "created_at" in data and hasattr(data["created_at"], "isoformat"):
                data["created_at"] = data["created_at"].isoformat()
            if "updated_at" in data and hasattr(data["updated_at"], "isoformat"):
                data["updated_at"] = data["updated_at"].isoformat()
            if "start_time" in data and hasattr(data["start_time"], "isoformat"):
                data["start_time"] = data["start_time"].isoformat()
            if "end_time" in data and hasattr(data["end_time"], "isoformat"):
                data["end_time"] = data["end_time"].isoformat()
            response = supabase.table("events").insert(data).execute()
            if response.data:
                return Event(**response.data[0])
            return None
        except Exception as e:
            print(f"Error creating event: {e}")
            return None

    # Issue vote operations
    @staticmethod
    def get_issue_votes(issue_id: str) -> List[IssueVote]:
        try:
            response = (
                supabase.table("issue_votes")
                .select("*")
                .eq("issue_id", issue_id)
                .execute()
            )
            return [IssueVote(**item) for item in response.data]
        except Exception as e:
            print(f"Error fetching issue votes: {e}")
            return []

    @staticmethod
    def create_issue_vote(vote: IssueVote) -> Optional[IssueVote]:
        try:
            data = vote.dict(exclude_unset=True)
            data["id"] = str(data["id"])
            data["issue_id"] = str(data["issue_id"])
            data["user_id"] = str(data["user_id"])
            # Convert datetime objects to ISO format strings
            if "created_at" in data and hasattr(data["created_at"], "isoformat"):
                data["created_at"] = data["created_at"].isoformat()
            response = supabase.table("issue_votes").insert(data).execute()
            if response.data:
                return IssueVote(**response.data[0])
            return None
        except Exception as e:
            print(f"Error creating issue vote: {e}")
            return None

    @staticmethod
    def update_issue_vote(
        user_id: str, issue_id: str, vote_value: int
    ) -> Optional[IssueVote]:
        try:
            # Use upsert to handle existing votes
            data = {"user_id": user_id, "issue_id": issue_id, "vote": vote_value}
            response = supabase.table("issue_votes").upsert(data).execute()
            if response.data:
                return IssueVote(**response.data[0])
            return None
        except Exception as e:
            print(f"Error updating issue vote: {e}")
            return None

    # Event RSVP operations
    @staticmethod
    def get_event_rsvps(event_id: str) -> List[EventRSVP]:
        try:
            response = (
                supabase.table("event_rsvps")
                .select("*")
                .eq("event_id", event_id)
                .execute()
            )
            return [EventRSVP(**item) for item in response.data]
        except Exception as e:
            print(f"Error fetching event RSVPs: {e}")
            return []

    @staticmethod
    def create_event_rsvp(rsvp: EventRSVP) -> Optional[EventRSVP]:
        try:
            data = rsvp.dict(exclude_unset=True)
            data["id"] = str(data["id"])
            data["event_id"] = str(data["event_id"])
            data["user_id"] = str(data["user_id"])
            # Convert datetime objects to ISO format strings
            if "created_at" in data and hasattr(data["created_at"], "isoformat"):
                data["created_at"] = data["created_at"].isoformat()
            if "updated_at" in data and hasattr(data["updated_at"], "isoformat"):
                data["updated_at"] = data["updated_at"].isoformat()
            response = supabase.table("event_rsvps").insert(data).execute()
            if response.data:
                return EventRSVP(**response.data[0])
            return None
        except Exception as e:
            print(f"Error creating event RSVP: {e}")
            return None

    @staticmethod
    def update_event_rsvp(
        user_id: str, event_id: str, status: str
    ) -> Optional[EventRSVP]:
        try:
            # Use upsert to handle existing RSVPs
            data = {"user_id": user_id, "event_id": event_id, "status": status}
            response = supabase.table("event_rsvps").upsert(data).execute()
            if response.data:
                return EventRSVP(**response.data[0])
            return None
        except Exception as e:
            print(f"Error updating event RSVP: {e}")
            return None

    # User points history operations
    @staticmethod
    def get_user_points_history(
        user_id: str, limit: int = 100
    ) -> List[UserPointsHistory]:
        try:
            response = (
                supabase.table("user_points_history")
                .select("*")
                .eq("user_id", user_id)
                .limit(limit)
                .execute()
            )
            return [UserPointsHistory(**item) for item in response.data]
        except Exception as e:
            print(f"Error fetching user points history: {e}")
            return []

    # Helper functions for common operations
    @staticmethod
    def award_points(
        user_id: str, action_type: str, points: int, reference_id: str = None
    ) -> bool:
        try:
            # Call the PostgreSQL function
            response = supabase.rpc(
                "award_points",
                {
                    "p_user_id": user_id,
                    "p_action_type": action_type,
                    "p_points": points,
                    "p_reference_id": reference_id,
                },
            ).execute()
            return True
        except Exception as e:
            print(f"Error awarding points: {e}")
            return False

    @staticmethod
    def get_markers_near_location(
        latitude: float, longitude: float, radius_meters: int = 1000, limit: int = 100
    ) -> List[AppMarker]:
        try:
            # Use PostGIS to find markers within radius
            response = (
                supabase.rpc(
                    "get_markers_near_point",
                    {"lat": latitude, "lng": longitude, "radius": radius_meters},
                )
                .limit(limit)
                .execute()
            )
            return [AppMarker(**item) for item in response.data]
        except Exception as e:
            print(f"Error fetching nearby markers: {e}")
            # Fallback to getting all markers if spatial query fails
            return SupabaseService.get_markers(limit)

    @staticmethod
    def get_user_by_email(email: str) -> Optional[User]:
        try:
            response = supabase.table("users").select("*").eq("email", email).execute()
            if response.data:
                return User(**response.data[0])
            return None
        except Exception as e:
            print(f"Error fetching user by email: {e}")
            return None

    # Authentication-based user operations
    @staticmethod
    def signup_user(email: str, password: str, username: str = None) -> Optional[dict]:
        """Create a user through Supabase Auth, which will trigger user table creation via triggers"""
        try:
            # Sign up through Supabase Auth
            response = supabase.auth.sign_up(
                {
                    "email": email,
                    "password": password,
                    "options": {"data": {"username": username}},
                }
            )

            if response.user:
                print(f"User created in auth system with ID: {response.user.id}")
                # The user table entry should be created automatically via triggers
                return {"user": response.user, "session": response.session}
            return None
        except Exception as e:
            print(f"Error signing up user: {e}")
            return None

    @staticmethod
    def signin_user(email: str, password: str) -> Optional[dict]:
        """Sign in a user through Supabase Auth"""
        try:
            response = supabase.auth.sign_in_with_password(
                {"email": email, "password": password}
            )

            if response.user:
                return {"user": response.user, "session": response.session}
            return None
        except Exception as e:
            print(f"Error signing in user: {e}")
            return None

    @staticmethod
    def get_authenticated_user() -> Optional[dict]:
        """Get the currently authenticated user"""
        try:
            response = supabase.auth.get_user()
            return response.user if response.user else None
        except Exception as e:
            print(f"Error getting authenticated user: {e}")
            return None
