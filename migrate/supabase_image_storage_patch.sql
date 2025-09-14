-- Image storage patch for EcoAction database
-- Run this in your Supabase SQL editor to add image support

-- Add image_url column to events table if it doesn't exist
DO $$ 
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'events' AND column_name = 'image_url'
    ) THEN
        ALTER TABLE events ADD COLUMN image_url TEXT;
    END IF;
END $$;

-- Create storage bucket for images (run this in Supabase Dashboard > Storage)
-- You'll need to manually create the bucket named 'images' in the Supabase dashboard
-- and set the following policies:

-- Storage policies for the 'images' bucket:
-- 1. Allow authenticated users to upload images
-- 2. Allow public read access to images

-- Note: You need to create the 'images' bucket manually in Supabase Dashboard
-- Then run these policies in the SQL editor:

-- Policy for uploading images (authenticated users only)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE tablename = 'objects' 
        AND schemaname = 'storage' 
        AND policyname = 'Users can upload images'
    ) THEN
        CREATE POLICY "Users can upload images" ON storage.objects
        FOR INSERT WITH CHECK (
            bucket_id = 'images' AND 
            auth.role() = 'authenticated'
        );
    END IF;
END $$;

-- Policy for public read access to images
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE tablename = 'objects' 
        AND schemaname = 'storage' 
        AND policyname = 'Public can view images'
    ) THEN
        CREATE POLICY "Public can view images" ON storage.objects
        FOR SELECT USING (bucket_id = 'images');
    END IF;
END $$;

-- Policy for users to delete their own images
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE tablename = 'objects' 
        AND schemaname = 'storage' 
        AND policyname = 'Users can delete their own images'
    ) THEN
        CREATE POLICY "Users can delete their own images" ON storage.objects
        FOR DELETE USING (
            bucket_id = 'images' AND 
            auth.uid()::text = (storage.foldername(name))[1]
        );
    END IF;
END $$;
