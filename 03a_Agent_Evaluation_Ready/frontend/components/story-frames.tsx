import { Loader2, Eye, Download } from 'lucide-react';

interface GeneratedImage {
  index: number;
  base64?: string;
  gcs_url?: string;
  format: string;
  stored_in_bucket?: boolean;
  gcs_error?: boolean; // Added for error handling
  error?: string; // Error message if generation failed
  placeholder?: boolean; // True if this is an error placeholder
}

interface StoryFramesProps {
  story: string;
  images?: (GeneratedImage | null)[];
  isGeneratingStory?: boolean;
  isGeneratingImages?: boolean;
  generationStatus?: string;
  expectedFrames?: number; // optional override for number of frames
}

// In your StoryFrames.tsx component

function splitStoryIntoFrames(story: string, frameCount: number): string[] {
  const frames: string[] = Array.from({ length: frameCount }, () => "");
  const trimmedStory = (story || '').trim();

  if (!trimmedStory) {
    return frames;
  }

  // New, improved logic: Split by [SCENE X] markers
  if (trimmedStory.includes('[SCENE 1]')) {
    // Use a regex to split by the scene markers.
    // The split results in an array where the first element is empty
    // and subsequent elements are the scene texts.
    const sceneTexts = trimmedStory.split(/\[SCENE \d+\]/g).filter(Boolean);
    
    sceneTexts.forEach((text, index) => {
      if (index < frameCount) {
        frames[index] = text.trim();
      }
    });
    return frames;
  }

  // Fallback for old story formats or errors
  console.warn("Story format doesn't contain [SCENE] markers. Falling back to paragraph splitting.");
  const paragraphs = trimmedStory.split(/\n\s*\n+/).filter(Boolean);
  if (paragraphs.length >= frameCount) {
    paragraphs.forEach((p, index) => {
      if (index < frameCount) frames[index] = p.trim();
    });
    return frames;
  }

  // Final fallback: split by sentences as before
  const sentences = trimmedStory.match(/[^.!?]+[.!?]+(?:\s+|$)/g) || [];
  const perFrame = Math.ceil(sentences.length / frameCount);
  for (let i = 0; i < frameCount; i++) {
    frames[i] = sentences.slice(i * perFrame, (i + 1) * perFrame).join(' ').trim();
  }

  return frames;
}

function splitStoryIntoFrames1(story: string, frameCount: number): string[] {
  const frames: string[] = Array.from({ length: frameCount }, () => "");
  const trimmed = (story || '').trim();
  if (!trimmed) return frames;

  // Prefer paragraph-based split
  const paragraphs = trimmed.split(/\n\s*\n+/).map(p => p.trim()).filter(Boolean);
  if (paragraphs.length >= frameCount) {
    // Distribute paragraphs sequentially into frames
    let frameIndex = 0;
    paragraphs.forEach((p) => {
      frames[frameIndex] = frames[frameIndex]
        ? `${frames[frameIndex]}\n\n${p}`
        : p;
      frameIndex = (frameIndex + 1) % frameCount;
    });
    return frames;
  }

  // Sentence-based split
  const sentences = trimmed.match(/[^.!?]+[.!?]+(?:\s+|$)/g) || [trimmed];
  const perFrame = Math.ceil(sentences.length / frameCount);
  for (let i = 0; i < frameCount; i++) {
    const start = i * perFrame;
    const end = Math.min((i + 1) * perFrame, sentences.length);
    if (start < sentences.length) {
      frames[i] = sentences.slice(start, end).join(' ').trim();
    }
  }

  // If still empty (very short story), split by characters
  if (!frames.some(Boolean)) {
    const chunkSize = Math.ceil(trimmed.length / frameCount);
    for (let i = 0; i < frameCount; i++) {
      const start = i * chunkSize;
      const end = Math.min((i + 1) * chunkSize, trimmed.length);
      frames[i] = trimmed.slice(start, end);
    }
  }

  return frames;
}

export default function StoryFrames({
  story,
  images = [],
  isGeneratingStory = false,
  isGeneratingImages = false,
  generationStatus = "",
  expectedFrames,
}: StoryFramesProps) {
  const frameCount = expectedFrames ?? (images.length > 0 ? images.length : 4);
  const storyFrames = splitStoryIntoFrames(story, frameCount);

  const openImageInNewTab = (image: GeneratedImage) => {
    try {
      const imageUrl = image.gcs_url || `data:image/${image.format};base64,${image.base64}`;
      const newTab = window.open();
      if (newTab) {
        newTab.document.write(`
          <html>
            <head><title>Story Frame</title></head>
            <body style="margin:0; display:flex; justify-content:center; align-items:center; min-height:100vh; background:#000;">
              <img src="${imageUrl}" style="max-width:100%; max-height:100%; object-fit:contain;" />
            </body>
          </html>
        `);
      }
    } catch (error) {
      console.error('Error opening image:', error);
    }
  };

  const downloadImage = (image: GeneratedImage, index: number) => {
    try {
      if (image.gcs_url) {
        window.open(image.gcs_url, '_blank');
      } else if (image.base64) {
        const link = document.createElement('a');
        link.href = `data:image/${image.format};base64,${image.base64}`;
        link.download = `story-frame-${index + 1}.${image.format}`;
        link.click();
      }
    } catch (error) {
      console.error('Error downloading image:', error);
    }
  };

  return (
    <div className="w-full space-y-8">
      <div className="flex items-center justify-between">
        <h2 className="text-2xl font-bold text-gray-900 dark:text-white">Generated Story</h2>
        {(isGeneratingImages || isGeneratingStory || generationStatus) && (
          <div className="text-sm text-blue-600 dark:text-blue-400">
            {generationStatus || (isGeneratingImages ? 'Generating images…' : isGeneratingStory ? 'Generating story…' : '')}
          </div>
        )}
      </div>

      {Array.from({ length: frameCount }).map((_, i) => {
        const img = images[i];
        const text = storyFrames[i];
        return (
          <div key={i} className="bg-orange-100/70 dark:bg-orange-900/20 rounded-2xl p-4 md:p-6 shadow-sm">
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4 md:gap-6">
              {/* Left: Story text */}
              <div className="bg-yellow-50 dark:bg-yellow-900/20 rounded-xl p-4 md:p-5">
                {text ? (
                  <div className="text-gray-800 dark:text-gray-200 whitespace-pre-wrap leading-relaxed">
                    {text}
                  </div>
                ) : (
                  <div className="h-full flex items-center justify-center text-gray-500 dark:text-gray-400">
                    {isGeneratingStory ? (
                      <div className="flex items-center gap-2 text-sm"><Loader2 className="h-5 w-5 animate-spin" /> Generating story…</div>
                    ) : (
                      <span className="italic">Story frame {i + 1} will appear here…</span>
                    )}
                  </div>
                )}
              </div>

              {/* Right: Image */}
              <div className="bg-yellow-50 dark:bg-yellow-900/20 rounded-xl p-2 md:p-3 relative min-h-[180px] md:min-h-[220px]">
                {img ? (
                  img.placeholder || img.error ? (
                    // Show error state for failed image generation
                    <div className="h-full w-full flex items-center justify-center rounded-lg bg-gray-200 dark:bg-gray-700">
                      <div className="text-center p-4">
                        <span className="text-gray-500 dark:text-gray-400 text-sm block mb-2">
                          Image generation failed
                        </span>
                        <span className="text-gray-400 dark:text-gray-500 text-xs">
                          Frame {i + 1}
                        </span>
                      </div>
                    </div>
                  ) : (
                  <div className="group relative h-full w-full overflow-hidden rounded-lg">
                    <img
                        src={img.gcs_url && !img.gcs_error ? img.gcs_url : (img.base64 ? `data:image/${img.format};base64,${img.base64}` : '')}
                      alt={`Story image ${i + 1}`}
                      className="h-full w-full object-cover"
                        onError={(e) => {
                          // If GCS URL fails, try base64
                          if (img.gcs_url && img.base64) {
                            console.log(`GCS URL failed for image ${i + 1}, falling back to base64`);
                            (e.target as HTMLImageElement).src = `data:image/${img.format};base64,${img.base64}`;
                            // Mark that GCS failed to prevent retry
                            img.gcs_error = true;
                          }
                        }}
                    />
                    <div className="absolute inset-0 bg-black/0 group-hover:bg-black/30 transition-opacity opacity-0 group-hover:opacity-100 flex items-center justify-center gap-2">
                      <button
                        onClick={() => openImageInNewTab(img)}
                        className="p-2 bg-white/20 hover:bg-white/30 rounded-full"
                        title="View full size"
                      >
                        <Eye className="h-4 w-4 text-white" />
                      </button>
                      <button
                        onClick={() => downloadImage(img, i)}
                        className="p-2 bg-white/20 hover:bg-white/30 rounded-full"
                        title="Download image"
                      >
                        <Download className="h-4 w-4 text-white" />
                      </button>
                    </div>
                  </div>
                  )
                ) : (
                  <div className="h-full w-full flex items-center justify-center rounded-lg bg-gray-200 dark:bg-gray-700">
                    {isGeneratingImages ? (
                      <div className="flex items-center gap-2 text-sm text-gray-600 dark:text-gray-300"><Loader2 className="h-5 w-5 animate-spin" /> Generating image…</div>
                    ) : (
                      <span className="text-gray-500 dark:text-gray-400 text-sm">Image {i + 1}</span>
                    )}
                  </div>
                )}
              </div>
            </div>
          </div>
        );
      })}
    </div>
  );
} 