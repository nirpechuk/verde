#!/usr/bin/env python3
"""
Final Boston Environmental Event Scraper

Uses Boston 311 CSV data and Claude API to create highly customized environmental events.
Each event description is generated dynamically by Claude based on the specific issue details.

Features:
- Reads Boston 311 CSV data with all available columns
- Intelligent categorization based on case_title, subject, reason, type
- Claude API integration for custom event descriptions
- Proper event scheduling and geographic clustering
"""

import asyncio
import aiohttp
import csv
import uuid
import os
from datetime import datetime, timedelta
from typing import List, Dict, Optional, Set
from dataclasses import dataclass
import json
import logging

from supabase_service import SupabaseService
from models import AppMarker, Event, MarkerType, EventCategory, EventStatus

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


@dataclass
class BostonIssue:
    """Represents a Boston 311 issue from CSV data"""
    case_enquiry_id: str
    open_dt: datetime
    case_status: str
    case_title: str
    subject: str
    reason: str
    type: str
    queue: str
    department: str
    location: str
    neighborhood: str
    location_street_name: str
    location_zipcode: str
    latitude: float
    longitude: float
    source: str
    closure_reason: str = ""
    submitted_photo: str = ""
    closed_photo: str = ""


class FinalBostonScraper:
    """Final scraper using Boston CSV data with Claude API for custom descriptions"""
    
    # Environmental issue mappings based on Boston 311 data patterns
    ENVIRONMENTAL_CATEGORIES = {
        EventCategory.cleanup: {
            "case_titles": [
                "Improper Storage of Trash (Barrels)", "CE Collection", "Graffiti Removal",
                "Requests for Street Cleaning", "Empty Litter Basket", "Pick up Dead Animal",
                "Abandoned Vehicles", "Bulk Item Collection", "Illegal Dumping",
                "Overflowing Litter Baskets", "Dirty Conditions"
            ],
            "subjects": [
                "Public Works Department", "Street Cleaning", "Graffiti", 
                "Highway Maintenance", "Code Enforcement"
            ],
            "keywords": [
                "trash", "garbage", "litter", "graffiti", "cleaning", "dumping",
                "abandoned", "dead animal", "debris", "collection", "removal"
            ]
        },
        EventCategory.advocacy: {
            "case_titles": [
                "Air Pollution Control", "Noise Disturbance", "Water Quality",
                "Industrial Waste", "Environmental Hazard", "Toxic Material",
                "Sewage/Septic", "Odor", "Chemical Spill"
            ],
            "subjects": [
                "Environmental Services", "Air Quality", "Water Quality",
                "Hazardous Materials", "Industrial Compliance"
            ],
            "keywords": [
                "pollution", "noise", "air quality", "water", "toxic", "hazard",
                "chemical", "industrial", "sewage", "odor", "contamination"
            ]
        },
        EventCategory.education: {
            "case_titles": [
                "Recycling", "Composting Program", "Environmental Education",
                "Green Initiative", "Sustainability Program"
            ],
            "subjects": [
                "Recycling", "Environmental Education", "Sustainability",
                "Green Programs", "Conservation"
            ],
            "keywords": [
                "recycling", "composting", "education", "green", "sustainability",
                "conservation", "program", "initiative", "awareness"
            ]
        }
    }

    def __init__(self, csv_file_path: str):
        self.csv_file_path = csv_file_path
        self.session: Optional[aiohttp.ClientSession] = None
        self.created_events_count = 0
        self.processed_issues_count = 0
        self.claude_api_key = os.getenv('CLAUDE_API_KEY')
        
        if not self.claude_api_key:
            logger.warning("CLAUDE_API_KEY not found in environment variables")

    async def __aenter__(self):
        self.session = aiohttp.ClientSession(
            timeout=aiohttp.ClientTimeout(total=60),
            headers={'User-Agent': 'Boston-Environmental-Scraper/1.0'}
        )
        return self

    async def __aexit__(self, exc_type, exc_val, exc_tb):
        if self.session:
            await self.session.close()

    def read_boston_csv(self, limit: int = 1000) -> List[BostonIssue]:
        """Read and parse Boston 311 CSV data"""
        logger.info(f"📊 Reading Boston CSV data from {self.csv_file_path}...")
        
        issues = []
        try:
            with open(self.csv_file_path, 'r', encoding='utf-8') as file:
                reader = csv.DictReader(file)
                
                for i, row in enumerate(reader):
                    if i >= limit:  # Limit for testing
                        break
                        
                    try:
                        # Skip if missing essential data
                        if not row.get('latitude') or not row.get('longitude'):
                            continue
                            
                        # Parse open date
                        open_dt = self._parse_date(row.get('open_dt', ''))
                        if not open_dt:
                            continue
                            
                        # Only process environmental issues
                        if not self._is_environmental_issue(row):
                            continue
                            
                        issue = BostonIssue(
                            case_enquiry_id=row.get('case_enquiry_id', ''),
                            open_dt=open_dt,
                            case_status=row.get('case_status', ''),
                            case_title=row.get('case_title', ''),
                            subject=row.get('subject', ''),
                            reason=row.get('reason', ''),
                            type=row.get('type', ''),
                            queue=row.get('queue', ''),
                            department=row.get('department', ''),
                            location=row.get('location', ''),
                            neighborhood=row.get('neighborhood', ''),
                            location_street_name=row.get('location_street_name', ''),
                            location_zipcode=row.get('location_zipcode', ''),
                            latitude=float(row['latitude']),
                            longitude=float(row['longitude']),
                            source=row.get('source', ''),
                            closure_reason=row.get('closure_reason', ''),
                            submitted_photo=row.get('submitted_photo', ''),
                            closed_photo=row.get('closed_photo', '')
                        )
                        issues.append(issue)
                        
                    except (ValueError, KeyError) as e:
                        logger.debug(f"Skipping malformed row {i}: {e}")
                        continue
                        
        except FileNotFoundError:
            logger.error(f"CSV file not found: {self.csv_file_path}")
            return []
        except Exception as e:
            logger.error(f"Error reading CSV file: {e}")
            return []
            
        logger.info(f"Found {len(issues)} environmental issues in Boston data")
        return issues

    def _parse_date(self, date_str: str) -> Optional[datetime]:
        """Parse date string from Boston CSV"""
        if not date_str:
            return None
            
        try:
            # Handle format: "2025-03-27 14:12:28"
            return datetime.strptime(date_str[:19], "%Y-%m-%d %H:%M:%S")
        except ValueError:
            try:
                # Handle date only format
                return datetime.strptime(date_str[:10], "%Y-%m-%d")
            except ValueError:
                return None

    def _is_environmental_issue(self, row: Dict[str, str]) -> bool:
        """Check if a Boston 311 issue is environmental"""
        case_title = row.get('case_title', '').lower()
        subject = row.get('subject', '').lower()
        reason = row.get('reason', '').lower()
        
        # Check against all environmental categories
        for category_data in self.ENVIRONMENTAL_CATEGORIES.values():
            # Check case titles
            for title in category_data['case_titles']:
                if title.lower() in case_title:
                    return True
                    
            # Check subjects
            for subj in category_data['subjects']:
                if subj.lower() in subject:
                    return True
                    
            # Check keywords
            text_to_check = f"{case_title} {subject} {reason}"
            for keyword in category_data['keywords']:
                if keyword in text_to_check:
                    return True
                    
        return False

    def categorize_issue(self, issue: BostonIssue) -> EventCategory:
        """Categorize Boston issue into event type"""
        case_title = issue.case_title.lower()
        subject = issue.subject.lower()
        reason = issue.reason.lower()
        
        # Check each category
        for category, data in self.ENVIRONMENTAL_CATEGORIES.items():
            # Check case titles first (most specific)
            for title in data['case_titles']:
                if title.lower() in case_title:
                    return category
                    
            # Check subjects
            for subj in data['subjects']:
                if subj.lower() in subject:
                    return category
                    
            # Check keywords
            text_to_check = f"{case_title} {subject} {reason}"
            for keyword in data['keywords']:
                if keyword in text_to_check:
                    return category
                    
        # Default to cleanup for environmental issues
        return EventCategory.cleanup

    async def generate_event_with_claude(self, issues: List[BostonIssue], category: EventCategory) -> Dict[str, str]:
        """Generate event title and description using Claude API with separate prompts"""
        if not self.claude_api_key:
            return self._generate_fallback_event(issues, category)
        
        # First, generate the description
        description = await self._generate_description(issues, category)
        if not description:
            return self._generate_fallback_event(issues, category)
        
        # Then, generate a title based on the description
        title = await self._generate_title(description, issues[0].neighborhood, category)
        if not title:
            return self._generate_fallback_event(issues, category)
        
        logger.info(f"✅ Successfully generated event with Claude")
        return {
            'title': title,
            'description': description
        }

    async def _generate_description(self, issues: List[BostonIssue], category: EventCategory) -> str:
        """Generate event description using Claude"""
        issue_summary = self._prepare_issue_summary(issues)
        
        # Create a simple list of specific issues
        issue_list = []
        for issue in issues:
            issue_list.append(f"• {issue.case_title}")
        
        prompt = f"""Write a concise event description for a community environmental event in {issues[0].neighborhood}.

SPECIFIC ISSUES TO ADDRESS:
{'\n'.join(issue_list)}

EVENT TYPE: {category.value}

Write a brief, engaging description that:
- Lists the specific issues being addressed
- Explains what participants will do
- Is community-focused (no single organizer) and engaging
- Includes simple preparation instructions if helpful
- Since there is not an organizer or leader, you can't assume that any supplies will be provided. You can ask people to bring anything extra that they do have though.

Keep it concise and actionable. Respond with ONLY the description text."""

        return await self._call_claude_api(prompt)

    async def _generate_title(self, description: str, neighborhood: str, category: EventCategory) -> str:
        """Generate event title based on description"""
        prompt = f"""Based on this event description and details, create a catchy event title:

DESCRIPTION: {description[:300]}...
NEIGHBORHOOD: {neighborhood}
CATEGORY: {category.value}

Create an engaging event title that:
- Is maximum 60 characters
- Does NOT include the address (that's displayed separately)
- Captures the essence of the event
- Is community-focused and action-oriented
- Mentions the neighborhood if it fits naturally
- If possible, make a fun pun or cool name; it should be light-hearted and engaging

Respond with ONLY the title text, no quotes or other formatting."""

        return await self._call_claude_api(prompt)

    async def _call_claude_api(self, prompt: str) -> str:
        """Make a simple API call to Claude and return the text response"""
        try:
            headers = {
                'Content-Type': 'application/json',
                'x-api-key': self.claude_api_key,
                'anthropic-version': '2023-06-01'
            }
            
            payload = {
                'model': 'claude-3-haiku-20240307',
                'max_tokens': 1000,
                'messages': [
                    {
                        'role': 'user',
                        'content': prompt
                    }
                ]
            }
            
            async with self.session.post(
                'https://api.anthropic.com/v1/messages',
                headers=headers,
                json=payload
            ) as response:
                if response.status == 200:
                    result = await response.json()
                    content = result['content'][0]['text'].strip()
                    return content
                else:
                    logger.warning(f"Claude API error: {response.status}")
                    return ""
                    
        except Exception as e:
            logger.error(f"Error calling Claude API: {e}")
            return ""

    def _prepare_issue_summary(self, issues: List[BostonIssue]) -> str:
        """Prepare issue data summary for Claude"""
        summary_parts = []
        
        for i, issue in enumerate(issues[:5]):  # Limit to 5 issues for prompt length
            summary_parts.append(f"""
Issue {i+1}:
- Type: {issue.case_title}
- Department: {issue.department}
- Details: {issue.reason}
- Status: {issue.case_status}
- Source: {issue.source}
""")
        
        if len(issues) > 5:
            summary_parts.append(f"... and {len(issues) - 5} more similar issues")
            
        return "\n".join(summary_parts)

    def _generate_fallback_event(self, issues: List[BostonIssue], category: EventCategory) -> Dict[str, str]:
        """Generate fallback event when Claude API is unavailable"""
        primary_issue = issues[0]
        neighborhood = primary_issue.neighborhood or "Community"
        
        if category == EventCategory.cleanup:
            title = f"{neighborhood} Environmental Cleanup"
            description = f"Join us for a community cleanup event in {neighborhood}! We're addressing {len(issues)} environmental issue(s) including {primary_issue.case_title.lower()}. Help us make our neighborhood cleaner and healthier."
        elif category == EventCategory.advocacy:
            title = f"{neighborhood} Environmental Action"
            description = f"Community meeting to address environmental concerns in {neighborhood}. We'll discuss {len(issues)} issue(s) including {primary_issue.case_title.lower()} and plan advocacy strategies."
        else:
            title = f"{neighborhood} Environmental Workshop"
            description = f"Educational workshop addressing environmental issues in {neighborhood}. Learn about {primary_issue.case_title.lower()} and how to prevent future problems."
            
        return {'title': title, 'description': description}

    def cluster_nearby_issues(self, issues: List[BostonIssue], max_distance_km: float = 0.5) -> List[List[BostonIssue]]:
        """Group nearby issues for single events"""
        if not issues:
            return []
            
        clusters = []
        used_indices = set()
        
        for i, issue in enumerate(issues):
            if i in used_indices:
                continue
                
            cluster = [issue]
            used_indices.add(i)
            
            # Find nearby issues of similar category
            issue_category = self.categorize_issue(issue)
            
            for j, other_issue in enumerate(issues):
                if j in used_indices or i == j:
                    continue
                    
                # Check if same category
                if self.categorize_issue(other_issue) != issue_category:
                    continue
                    
                # Check distance
                distance = self._haversine_distance(
                    issue.latitude, issue.longitude,
                    other_issue.latitude, other_issue.longitude
                )
                
                if distance <= max_distance_km:
                    cluster.append(other_issue)
                    used_indices.add(j)
                    
            clusters.append(cluster)
            
        return clusters

    def _haversine_distance(self, lat1: float, lng1: float, lat2: float, lng2: float) -> float:
        """Calculate distance between two points in kilometers"""
        from math import radians, cos, sin, asin, sqrt
        
        lat1, lng1, lat2, lng2 = map(radians, [lat1, lng1, lat2, lng2])
        
        dlat = lat2 - lat1
        dlng = lng2 - lng1
        a = sin(dlat/2)**2 + cos(lat1) * cos(lat2) * sin(dlng/2)**2
        c = 2 * asin(sqrt(a))
        
        return c * 6371  # Earth's radius in km

    async def create_event_from_cluster(self, cluster: List[BostonIssue]) -> Optional[Event]:
        """Create an event from a cluster of related issues"""
        if not cluster:
            return None
            
        # Determine event category
        category = self.categorize_issue(cluster[0])
        
        # Calculate center point
        center_lat = sum(issue.latitude for issue in cluster) / len(cluster)
        center_lng = sum(issue.longitude for issue in cluster) / len(cluster)
        
        # Generate event details using Claude API
        event_data = await self.generate_event_with_claude(cluster, category)
        
        # Schedule event for next weekend
        now = datetime.now()
        days_until_saturday = (5 - now.weekday()) % 7
        if days_until_saturday == 0:
            days_until_saturday = 7
            
        event_start = now.replace(hour=10, minute=0, second=0, microsecond=0) + \
                     timedelta(days=days_until_saturday)
        event_end = event_start + timedelta(hours=3)
        
        try:
            # Create marker
            marker = AppMarker(
                id=uuid.uuid4(),
                type=MarkerType.event,
                latitude=center_lat,
                longitude=center_lng,
                created_by=uuid.uuid4(),
                created_at=datetime.now(),
                updated_at=datetime.now()
            )
            
            created_marker = SupabaseService.create_marker(marker)
            if not created_marker:
                return None
                
            # Create event
            event = Event(
                id=uuid.uuid4(),
                marker_id=created_marker.id,
                title=event_data['title'],
                description=event_data['description'],
                category=category,
                start_time=event_start,
                end_time=event_end,
                max_participants=30 if category == EventCategory.cleanup else 25,
                current_participants=0,
                status=EventStatus.upcoming,
                created_at=datetime.now(),
                updated_at=datetime.now()
            )
            
            created_event = SupabaseService.create_event(event)
            if created_event:
                self.created_events_count += 1
                logger.info(f"✅ Created event: {created_event.title}")
                
            return created_event
            
        except Exception as e:
            logger.error(f"Failed to create event: {e}")
            return None

    async def process_boston_data(self, limit: int = 100) -> List[Event]:
        """Process Boston CSV data and create events"""
        logger.info("🏙️ Processing Boston 311 data...")
        
        # Read CSV data
        issues = self.read_boston_csv(limit)
        
        if not issues:
            logger.info("No environmental issues found in Boston data")
            return []
            
        self.processed_issues_count = len(issues)
        
        # Use all issues for proof of concept (not just recent ones)
        logger.info(f"Processing all {len(issues)} environmental issues for proof of concept")
        
        # Cluster nearby similar issues
        clusters = self.cluster_nearby_issues(issues)
        logger.info(f"Created {len(clusters)} issue clusters")
        
        # Create events from clusters
        created_events = []
        for i, cluster in enumerate(clusters):
            if len(cluster) >= 1:  # Create events for single issues or clusters
                logger.info(f"Processing cluster {i+1}/{len(clusters)} with {len(cluster)} issue(s)")
                event = await self.create_event_from_cluster(cluster)
                if event:
                    created_events.append(event)
                    
                # Rate limiting for Claude API
                await asyncio.sleep(1.0)
                
        return created_events


async def main():
    """Main function"""
    print("🏙️ Final Boston Environmental Event Scraper")
    print("=" * 50)
    
    csv_file = "/Users/npechuk/src/hackmit2025/worker/bostondata.csv"
    
    async with FinalBostonScraper(csv_file) as scraper:
        events = await scraper.process_boston_data(limit=100)
        
        print(f"\n📊 Final Scraping Results:")
        print(f"Total issues processed: {scraper.processed_issues_count}")
        print(f"Events created: {len(events)}")
        
        if events:
            print(f"\n🎉 Created {len(events)} customized events:")
            for i, event in enumerate(events[:5]):  # Show first 5
                print(f"\n{i+1}. {event.title}")
                print(f"   Category: {event.category}")
                print(f"   Description: {event.description[:100]}...")
                
            print(f"\n✨ All events created with Claude-generated descriptions!")
            print("Check your Supabase dashboard to see the full events.")
        else:
            print("⚠️  No events were created. Check your data and configuration.")


if __name__ == "__main__":
    asyncio.run(main())
