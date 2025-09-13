#!/usr/bin/env python3
"""
Simple debug script for Boston Event Scraper using urllib instead of aiohttp
"""

import urllib.request
import csv
import logging
from io import StringIO
from typing import List, Dict
from datetime import datetime, timedelta

# Set up logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def fetch_sample_data(limit: int = 500) -> List[Dict]:
    """Fetch a sample of Boston 311 data"""
    url = "https://data.boston.gov/dataset/8048697b-ad64-4bfc-b090-ee00169f2323/resource/c9509ab4-6f6d-4b97-979a-0cf2a10c922b/download/311_service_requests_2024.csv"
    
    logger.info(f"🔍 Fetching Boston 311 data (limit: {limit})...")
    
    try:
        with urllib.request.urlopen(url) as response:
            csv_content = response.read().decode('utf-8')
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

def analyze_data_structure(rows: List[Dict]) -> None:
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

def test_environmental_filtering(rows: List[Dict]) -> List[Dict]:
    """Test environmental issue filtering"""
    logger.info("🌱 Testing environmental filtering...")
    
    # Environmental categories
    ENVIRONMENTAL_CATEGORIES = {
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
    
    environmental_issues = []
    total_checked = 0
    
    for row in rows:
        total_checked += 1
        
        subject = (row.get('Subject', '') or '').lower()
        reason = (row.get('Reason', '') or '').lower()
        department = (row.get('Department', '') or '').lower()
        
        # Check against all environmental categories
        is_environmental = False
        for category_data in ENVIRONMENTAL_CATEGORIES.values():
            # Check subjects
            for env_subject in category_data['subjects']:
                if env_subject.lower() in subject:
                    is_environmental = True
                    break
                    
            # Check reasons
            if not is_environmental:
                for env_reason in category_data['reasons']:
                    if env_reason.lower() in reason:
                        is_environmental = True
                        break
                        
            # Check departments
            if not is_environmental:
                for env_dept in category_data['departments']:
                    if env_dept.lower() in department:
                        is_environmental = True
                        break
            
            if is_environmental:
                break
        
        if is_environmental:
            environmental_issues.append(row)
            logger.info(f"✅ Found environmental issue: Subject='{row.get('Subject')}', Reason='{row.get('Reason')}', Dept='{row.get('Department')}'")
    
    logger.info(f"📊 Environmental filtering results:")
    logger.info(f"  Total rows checked: {total_checked}")
    logger.info(f"  Environmental issues found: {len(environmental_issues)}")
    
    return environmental_issues

def main():
    """Main debug function"""
    logger.info("🚀 Starting Boston 311 scraper debug...")
    
    # Step 1: Fetch sample data
    sample_data = fetch_sample_data(limit=500)
    if not sample_data:
        logger.error("❌ Failed to fetch data")
        return
    
    # Step 2: Analyze data structure
    analyze_data_structure(sample_data)
    
    # Step 3: Test environmental filtering
    environmental_issues = test_environmental_filtering(sample_data)
    
    # Step 4: Summary
    logger.info("📋 Debug Summary:")
    logger.info(f"  Total sample data: {len(sample_data)}")
    logger.info(f"  Environmental issues: {len(environmental_issues)}")
    
    if environmental_issues:
        logger.info("✅ Environmental filtering is working!")
        for i, issue in enumerate(environmental_issues[:3]):
            logger.info(f"  Example {i+1}: {issue.get('Subject')} - {issue.get('Reason')}")
    else:
        logger.warning("⚠️  No environmental issues found - may need to adjust filtering criteria")

if __name__ == "__main__":
    main()
