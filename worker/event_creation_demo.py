#!/usr/bin/env python3
"""
Event Creation Demonstration

This script demonstrates how to create environmental events using the
environmental crowdsourcing platform's database schema.

The process involves:
1. Creating a marker (location) for the event
2. Creating the event with proper details
3. Optionally creating RSVPs and awarding points

Requirements:
- Supabase service key in .env file
- Valid user ID (from auth system)
"""

import uuid
from datetime import datetime, timedelta
from supabase_service import SupabaseService
from models import AppMarker, Event, EventRSVP, MarkerType, EventCategory, EventStatus


def create_sample_event():
    """
    Creates a sample environmental cleanup event with all necessary components.
    """
    print("🌱 Environmental Event Creation Demo")
    print("=" * 50)
    
    # Step 1: Create a marker (location) for the event
    print("\n📍 Step 1: Creating location marker...")
    
    # Sample coordinates (Boston Common area)
    latitude = 42.3555
    longitude = -71.0640
    
    # You would typically get this from the authenticated user
    # For demo purposes, we'll use a sample UUID
    creator_user_id = str(uuid.uuid4())
    print(f"Using creator user ID: {creator_user_id}")
    
    marker = AppMarker(
        id=uuid.uuid4(),
        type=MarkerType.event,
        latitude=latitude,
        longitude=longitude,
        created_by=uuid.UUID(creator_user_id),
        created_at=datetime.now(),
        updated_at=datetime.now()
    )
    
    created_marker = SupabaseService.create_marker(marker)
    if not created_marker:
        print("❌ Failed to create marker")
        return None
    
    print(f"✅ Marker created with ID: {created_marker.id}")
    
    # Step 2: Create the event
    print("\n🎯 Step 2: Creating environmental event...")
    
    # Event details
    event_start = datetime.now() + timedelta(days=7)  # Event in one week
    event_end = event_start + timedelta(hours=3)      # 3-hour event
    
    event = Event(
        id=uuid.uuid4(),
        marker_id=created_marker.id,
        title="Boston Common Cleanup Drive",
        description="Join us for a community cleanup event at Boston Common! We'll provide all supplies including gloves, trash bags, and pickup tools. Help us keep our beautiful park clean and green. Refreshments will be provided after the cleanup.",
        category=EventCategory.cleanup,
        start_time=event_start,
        end_time=event_end,
        max_participants=50,
        current_participants=0,
        status=EventStatus.upcoming,
        created_at=datetime.now(),
        updated_at=datetime.now()
    )
    
    created_event = SupabaseService.create_event(event)
    if not created_event:
        print("❌ Failed to create event")
        return None
    
    print(f"✅ Event created with ID: {created_event.id}")
    print(f"   Title: {created_event.title}")
    print(f"   Category: {created_event.category}")
    print(f"   Start Time: {created_event.start_time}")
    print(f"   Max Participants: {created_event.max_participants}")
    
    # Step 3: Award points to the event creator
    print("\n🏆 Step 3: Awarding points to event creator...")
    
    points_awarded = SupabaseService.award_points(
        user_id=creator_user_id,
        action_type="create_event",
        points=25,  # 25 points for creating an event
        reference_id=str(created_event.id)
    )
    
    if points_awarded:
        print("✅ 25 points awarded for event creation")
    else:
        print("⚠️  Points award failed (user may not exist in system)")
    
    # Step 4: Demonstrate RSVP creation
    print("\n📝 Step 4: Creating sample RSVP...")
    
    # Sample participant RSVP
    participant_user_id = str(uuid.uuid4())
    
    rsvp = EventRSVP(
        id=uuid.uuid4(),
        event_id=created_event.id,
        user_id=uuid.UUID(participant_user_id),
        status="going",
        created_at=datetime.now(),
        updated_at=datetime.now()
    )
    
    created_rsvp = SupabaseService.create_event_rsvp(rsvp)
    if created_rsvp:
        print(f"✅ RSVP created for user: {participant_user_id}")
        print(f"   Status: {created_rsvp.status}")
    else:
        print("⚠️  RSVP creation failed")
    
    print("\n🎉 Event creation demonstration completed!")
    print(f"Event ID: {created_event.id}")
    print(f"Marker ID: {created_marker.id}")
    
    return created_event


def create_advocacy_event():
    """
    Creates a sample advocacy event to demonstrate different event types.
    """
    print("\n🗣️  Creating Advocacy Event Demo")
    print("-" * 40)
    
    # Create marker for advocacy event (City Hall area)
    marker = AppMarker(
        id=uuid.uuid4(),
        type=MarkerType.event,
        latitude=42.3601,  # Boston City Hall
        longitude=-71.0589,
        created_by=uuid.uuid4(),
        created_at=datetime.now(),
        updated_at=datetime.now()
    )
    
    created_marker = SupabaseService.create_marker(marker)
    if not created_marker:
        print("❌ Failed to create advocacy event marker")
        return None
    
    # Create advocacy event
    event_start = datetime.now() + timedelta(days=14)  # Event in two weeks
    event_end = event_start + timedelta(hours=2)       # 2-hour event
    
    event = Event(
        id=uuid.uuid4(),
        marker_id=created_marker.id,
        title="Climate Action Town Hall",
        description="Join local environmental advocates and city council members to discuss climate action initiatives in Boston. Learn about upcoming green infrastructure projects and how you can get involved in local environmental policy.",
        category=EventCategory.advocacy,
        start_time=event_start,
        end_time=event_end,
        max_participants=100,
        current_participants=0,
        status=EventStatus.upcoming,
        created_at=datetime.now(),
        updated_at=datetime.now()
    )
    
    created_event = SupabaseService.create_event(event)
    if created_event:
        print(f"✅ Advocacy event created: {created_event.title}")
        return created_event
    else:
        print("❌ Failed to create advocacy event")
        return None


def demonstrate_event_queries():
    """
    Demonstrates how to query and retrieve events from the database.
    """
    print("\n🔍 Event Query Demonstration")
    print("-" * 40)
    
    # Get all events
    events = SupabaseService.get_events(limit=10)
    print(f"📊 Found {len(events)} events in database")
    
    for event in events:
        print(f"   • {event.title} ({event.category}) - {event.status}")
    
    # Get events near a location (if spatial queries are working)
    print("\n📍 Searching for events near Boston Common...")
    nearby_markers = SupabaseService.get_markers_near_location(
        latitude=42.3555,
        longitude=-71.0640,
        radius_meters=5000,  # 5km radius
        limit=10
    )
    
    event_markers = [m for m in nearby_markers if m.type == MarkerType.event]
    print(f"Found {len(event_markers)} event markers within 5km")


if __name__ == "__main__":
    try:
        print("Starting Environmental Event Creation Demo...")
        print("Make sure you have SUPABASE_SERVICE_KEY in your .env file!")
        
        # Create main cleanup event
        cleanup_event = create_sample_event()
        
        # Create advocacy event
        advocacy_event = create_advocacy_event()
        
        # Demonstrate queries
        demonstrate_event_queries()
        
        print("\n✨ Demo completed successfully!")
        print("\nNext steps:")
        print("1. Check your Supabase dashboard to see the created events")
        print("2. Try creating RSVPs for the events")
        print("3. Test the points system by creating users first")
        
    except Exception as e:
        print(f"\n❌ Demo failed with error: {e}")
        print("Make sure:")
        print("1. Your .env file contains SUPABASE_SERVICE_KEY")
        print("2. Your Supabase database is set up with the correct schema")
        print("3. RLS policies allow service key operations")
