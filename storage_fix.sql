-- Fix storage bucket access issues
-- Run this in Supabase SQL Editor

-- Ensure the bucket allows public access
UPDATE storage.buckets 
SET public = true 
WHERE id = 'images';

-- Drop existing policies that might be blocking access
DROP POLICY IF EXISTS "Public can view images" ON storage.objects;
DROP POLICY IF EXISTS "Users can upload images" ON storage.objects;
DROP POLICY IF EXISTS "Users can delete their own images" ON storage.objects;

-- Create new, simpler policies
CREATE POLICY "Public Access" ON storage.objects
FOR SELECT USING (bucket_id = 'images');

CREATE POLICY "Authenticated Upload" ON storage.objects
FOR INSERT WITH CHECK (
    bucket_id = 'images' AND 
    auth.role() = 'authenticated'
);

CREATE POLICY "Users Delete Own" ON storage.objects
FOR DELETE USING (
    bucket_id = 'images' AND 
    auth.uid()::text = (storage.foldername(name))[1]
);
