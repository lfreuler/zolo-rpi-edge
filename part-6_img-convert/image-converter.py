#!/usr/bin/env python3
"""
ZoLo Image Converter
Resizes images from source to destination directory
Preserves directory structure including spaces and special characters
Runs daily via cron
"""

import os
import sys
import logging
from pathlib import Path
from datetime import datetime
from PIL import Image
import hashlib

# Configuration
SOURCE_DIR = os.getenv('SOURCE_DIR', '/data/source')
DEST_DIR = os.getenv('DEST_DIR', '/data/destination')
MAX_WIDTH = int(os.getenv('MAX_WIDTH', '1920'))
MAX_HEIGHT = int(os.getenv('MAX_HEIGHT', '1080'))
QUALITY = int(os.getenv('QUALITY', '85'))
FORMATS = os.getenv('FORMATS', 'jpg,jpeg,png,webp').lower().split(',')
LOG_LEVEL = os.getenv('LOG_LEVEL', 'INFO')

# Setup Logging with UTF-8 encoding
logging.basicConfig(
    level=getattr(logging, LOG_LEVEL),
    format='%(asctime)s [%(levelname)s] %(message)s',
    handlers=[
        logging.StreamHandler(sys.stdout),
        logging.FileHandler('/var/log/image-converter.log', encoding='utf-8')
    ]
)
logger = logging.getLogger(__name__)


class ImageConverter:
    def __init__(self):
        self.source = Path(SOURCE_DIR)
        self.dest = Path(DEST_DIR)
        self.stats = {
            'total': 0,
            'converted': 0,
            'skipped': 0,
            'errors': 0
        }
        
    def should_process(self, source_file, dest_file):
        """Check if file needs processing"""
        if not dest_file.exists():
            return True
            
        # Check if source is newer than destination
        if source_file.stat().st_mtime > dest_file.stat().st_mtime:
            return True
            
        return False
    
    def resize_image(self, source_path, dest_path):
        """Resize single image"""
        try:
            with Image.open(source_path) as img:
                # Get original dimensions
                orig_width, orig_height = img.size
                
                # Convert RGBA to RGB if saving as JPEG
                if img.mode == 'RGBA' and dest_path.suffix.lower() in ['.jpg', '.jpeg']:
                    img = img.convert('RGB')
                
                # Calculate new size maintaining aspect ratio
                img.thumbnail((MAX_WIDTH, MAX_HEIGHT), Image.Resampling.LANCZOS)
                
                # Save with optimization
                save_kwargs = {
                    'quality': QUALITY,
                    'optimize': True
                }
                
                if dest_path.suffix.lower() in ['.jpg', '.jpeg']:
                    save_kwargs['progressive'] = True
                
                img.save(dest_path, **save_kwargs)
                
                return True
                
        except Exception as e:
            logger.error(f"Failed to process {source_path}: {e}")
            return False
    
    def process_directory(self):
        """Process all images in source directory, preserving structure"""
        logger.info("="*60)
        logger.info("ZoLo Image Converter - Starting new run")
        logger.info(f"Source: {self.source}")
        logger.info(f"Destination: {self.dest}")
        logger.info(f"Max dimensions: {MAX_WIDTH}x{MAX_HEIGHT}")
        logger.info(f"Quality: {QUALITY}%")
        logger.info("="*60)
        
        if not self.source.exists():
            logger.error(f"Source directory does not exist: {self.source}")
            return
        
        # Ensure destination exists
        self.dest.mkdir(parents=True, exist_ok=True)
        
        # Find all image files recursively
        image_files = []
        logger.info(f"Scanning for images in: {self.source}")
        
        for ext in FORMATS:
            # Case insensitive search
            found_lower = list(self.source.rglob(f"*.{ext}"))
            found_upper = list(self.source.rglob(f"*.{ext.upper()}"))
            image_files.extend(found_lower)
            image_files.extend(found_upper)
            
            if found_lower or found_upper:
                logger.info(f"  Found {len(found_lower) + len(found_upper)} .{ext} files")
        
        self.stats['total'] = len(image_files)
        logger.info(f"Total images found: {self.stats['total']}")
        
        if self.stats['total'] == 0:
            logger.warning("No images found to process!")
            logger.info(f"Check if source directory has images: {self.source}")
            logger.info(f"Supported formats: {', '.join(FORMATS)}")
            return
        
        logger.info("")
        logger.info("Processing images...")
        logger.info("")
        
        # Process each image
        for idx, source_file in enumerate(image_files, 1):
            try:
                # Get relative path from source (preserves directory structure)
                relative_path = source_file.relative_to(self.source)
                dest_file = self.dest / relative_path
                
                # Log with full path to show structure
                logger.info(f"[{idx}/{self.stats['total']}] {relative_path}")
                
                # Create subdirectories if needed (preserves structure)
                dest_file.parent.mkdir(parents=True, exist_ok=True)
                
                # Check if processing needed
                if not self.should_process(source_file, dest_file):
                    logger.info(f"  ↳ Skipped (already up-to-date)")
                    self.stats['skipped'] += 1
                    continue
                
                # Get file size before
                size_before = source_file.stat().st_size
                
                # Resize image
                if self.resize_image(source_file, dest_file):
                    size_after = dest_file.stat().st_size
                    reduction = ((size_before - size_after) / size_before) * 100
                    
                    logger.info(f"  ↳ Success: {size_before/1024:.1f}KB → {size_after/1024:.1f}KB ({reduction:.1f}% reduction)")
                    self.stats['converted'] += 1
                else:
                    logger.error(f"  ↳ Failed to convert")
                    self.stats['errors'] += 1
                    
            except Exception as e:
                logger.error(f"  ↳ Error processing {source_file}: {e}")
                self.stats['errors'] += 1
        
        # Final statistics
        logger.info("")
        logger.info("="*60)
        logger.info("Processing complete!")
        logger.info(f"Total files: {self.stats['total']}")
        logger.info(f"Converted: {self.stats['converted']}")
        logger.info(f"Skipped: {self.stats['skipped']}")
        logger.info(f"Errors: {self.stats['errors']}")
        logger.info("="*60)


def main():
    """Main entry point"""
    converter = ImageConverter()
    converter.process_directory()


if __name__ == '__main__':
    main()