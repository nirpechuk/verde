#!/usr/bin/env python3
"""
Debug script for Boston Event Scraper
Tests data fetching and environmental filtering without creating events
"""

import asyncio
import aiohttp
import csv
import logging
from io import StringIO
from typing import List, Dict, Optional
from datetime import datetime, timedelta

# Set up logging
logging.basicConfig(level=logging.DEBUG)
logger = logging.getLogger(__name__)

class BostonDebugger:
    def __init__(self):
        self.BOSTON_311_URL = "https://data.boston.gov/dataset/8048697b-ad64-4bfc-b090-ee00169f2323/resource/c9509ab4-6f6d-4b97-979a-0cf2a10c922b/download/311_service_requests_2024.csv"
        
        # Environmental categories from the main scraper
        self.ENVIRONMENTAL_CATEGORIES = {
            'cleanup': {
                'subjects': ['Sanitation', 'Trash', 'Litter', 'Graffiti', 'Illegal Dumping'],
                'reasons': ['Overflowing Trash', 'Missed Pickup', 'Illegal Dumping', 'Graffiti Removal'],
                'departments': ['Public Works Department', 'Parks & Recreation Department']
            },
            'advocacy': {
                'subjects': ['Environmental Services', 'Air Quality', 'Water Quality', 'Noise'],
                'reasons': ['Air Pollution', 'Water Contamination', 'Noise Complaint'],
                'departments': ['Environment Department', 'Inspectional Services Dept']
            },
            'education': {
                'subjects': ['Public Health', 'Education'],
                'reasons': ['Health Hazard', 'Educational Program'],
                'departments': ['Public Health Commission']
            }
        }

    async def fetch_sample_data(self, limit: int = 1000) -> List[Dict]:
        """Fetch a sample of Boston 311 data for debugging"""
        logger.info(f"🔍 Fetching sample Boston 311 data (limit: {limit})...")
        
        try:
            async with aiohttp.ClientSession() as session:
                async with session.get(self.BOSTON_311_URL) as response:
                    if response.status != 200:
                        logger.error(f"Failed to fetch data: {response.status}")
                        return []
                    
                    csv_content = await response.text()
                    logger.info(f"📄 CSV content length: {len(csv_content)} characters")
                    
                    # Parse CSV
                    csv_reader = csv.DictReader(StringIO(csv_content))
                    rows = []
                    
                    for i, row in enumerate(csv_reader):
                        if i >= limit:
                            break
                        rows.append(row)
                        
                        # Log first few rows for inspection
                        if i < 3:
                            logger.info(f"📋 Sample row {i+1}: {dict(list(row.items())[:5])}")
                    
                    logger.info(f"📊 Total rows fetched: {len(rows)}")
                    return rows
                    
        except Exception as e:
            logger.error(f"Error fetching data: {e}")
            return []

    def analyze_data_structure(self, rows: List[Dict]) -> None:
        """Analyze the structure of Boston 311 data"""
        if not rows:
            logger.error("No data to analyze")
            return
            
        logger.info("🔍 Analyzing data structure...")
        
        # Get column names
        columns = list(rows[0].keys())
        logger.info(f"📋 Available columns ({len(columns)}): {columns}")
        
        # Analyze key environmental fields
        subjects = set()
        reasons = set()
        departments = set()
        
        for row in rows[:100]:  # Sample first 100 rows
            if row.get('Subject'):
                subjects.add(row['Subject'])
            if row.get('Reason'):
                reasons.add(row['Reason'])
            if row.get('Department'):
                departments.add(row['Department'])
        
        logger.info(f"🏷️  Unique Subjects (sample): {sorted(list(subjects))[:10]}")
        logger.info(f"🏷️  Unique Reasons (sample): {sorted(list(reasons))[:10]}")
        logger.info(f"🏷️  Unique Departments (sample): {sorted(list(departments))[:10]}")

    def test_environmental_filtering(self, rows: List[Dict]) -> List[Dict]:
        """Test environmental issue filtering"""
        logger.info("🌱 Testing environmental filtering...")
        
        environmental_issues = []
        total_checked = 0
        
        for row in rows:
            total_checked += 1
            
            if self._is_environmental_issue(row):
                environmental_issues.append(row)
                logger.info(f"✅ Found environmental issue: Subject='{row.get('Subject')}', Reason='{row.get('Reason')}', Dept='{row.get('Department')}'")
        
        logger.info(f"📊 Environmental filtering results:")
        logger.info(f"  Total rows checked: {total_checked}")
        logger.info(f"  Environmental issues found: {len(environmental_issues)}")
        
        return environmental_issues

    def _is_environmental_issue(self, row: Dict) -> bool:
        """Check if a Boston 311 issue is environmental"""
        subject = (row.get('Subject', '') or '').lower()
        reason = (row.get('Reason', '') or '').lower()
        department = (row.get('Department', '') or '').lower()
        
        # Check against all environmental categories
        for category_data in self.ENVIRONMENTAL_CATEGORIES.values():
            # Check subjects
            for env_subject in category_data['subjects']:
                if env_subject.lower() in subject:
                    return True
                    
            # Check reasons
            for env_reason in category_data['reasons']:
                if env_reason.lower() in reason:
                    return True
                    
            # Check departments
            for env_dept in category_data['departments']:
                if env_dept.lower() in department:
                    return True
                    
        return False

    def test_date_filtering(self, rows: List[Dict]) -> List[Dict]:
        """Test date filtering for recent issues"""
        logger.info("📅 Testing date filtering...")
        
        cutoff_date = datetime.now() - timedelta(days=30)
        recent_issues = []
        
        for row in rows:
            date_str = row.get('open_dt', '')
            if date_str:
                try:
                    # Try parsing Boston date format
                    issue_date = datetime.strptime(date_str, '%Y-%m-%d %H:%M:%S')
                    if issue_date >= cutoff_date:
                        recent_issues.append(row)
                except ValueError:
                    # Try alternative formats
                    try:
                        issue_date = datetime.strptime(date_str.split('T')[0], '%Y-%m-%d')
                        if issue_date >= cutoff_date:
                            recent_issues.append(row)
                    except ValueError:
                        continue
        
        logger.info(f"📊 Date filtering results:")
        logger.info(f"  Cutoff date: {cutoff_date.strftime('%Y-%m-%d')}")
        logger.info(f"  Recent issues found: {len(recent_issues)}")
        
        return recent_issues

async def main():
    """Main debug function"""
    logger.info("🚀 Starting Boston 311 scraper debug...")
    
    debugger = BostonDebugger()
    
    # Step 1: Fetch sample data
    sample_data = await debugger.fetch_sample_data(limit=1000)
    if not sample_data:
        logger.error("❌ Failed to fetch data")
        return
    
    # Step 2: Analyze data structure
    debugger.analyze_data_structure(sample_data)
    
    # Step 3: Test date filtering
    recent_issues = debugger.test_date_filtering(sample_data)
    
    # Step 4: Test environmental filtering on recent issues
    if recent_issues:
        environmental_issues = debugger.test_environmental_filtering(recent_issues)
    else:
        logger.warning("⚠️  No recent issues found, testing environmental filtering on all data")
        environmental_issues = debugger.test_environmental_filtering(sample_data)
    
    # Step 5: Summary
    logger.info("📋 Debug Summary:")
    logger.info(f"  Total sample data: {len(sample_data)}")
    logger.info(f"  Recent issues (30 days): {len(recent_issues) if recent_issues else 0}")
    logger.info(f"  Environmental issues: {len(environmental_issues)}")
    
    if environmental_issues:
        logger.info("✅ Environmental filtering is working!")
        for i, issue in enumerate(environmental_issues[:3]):
            logger.info(f"  Example {i+1}: {issue.get('Subject')} - {issue.get('Reason')}")
    else:
        logger.warning("⚠️  No environmental issues found - may need to adjust filtering criteria")

if __name__ == "__main__":
    asyncio.run(main())
