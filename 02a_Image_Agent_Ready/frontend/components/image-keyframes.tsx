import { Loader2, Download, Eye } from 'lucide-react';

interface GeneratedImage {
  index: number;
  base64?: string;
  gcs_url?: string;
  format: string;
  stored_in_bucket?: boolean;
}

interface ImageKeyframesProps {
  images?: GeneratedImage[];
  isGenerating?: boolean;
  generationStatus?: string;
}

export default function ImageKeyframes({ 
  images = [], 
  isGenerating = false, 
  generationStatus = "" 
}: ImageKeyframesProps) {
  const fallbackKeyframes = [
    { id: 1, title: "Neon City" },
    { id: 2, title: "The Discovery" },
    { id: 3, title: "Crystal Code" },
    { id: 4, title: "The Architects" },
  ];

  const displayImages = images.length > 0 ? images : [];
  const showPlaceholders = images.length === 0 && !isGenerating;

  const downloadImage = (image: GeneratedImage, index: number) => {
    try {
      if (image.gcs_url) {
        // For GCS URLs, open in new tab for download
        window.open(image.gcs_url, '_blank');
      } else if (image.base64) {
        // For base64, create download link
        const link = document.createElement('a');
        link.href = `data:image/${image.format};base64,${image.base64}`;
        link.download = `story-keyframe-${index + 1}.${image.format}`;
        link.click();
      }
    } catch (error) {
      console.error('Error downloading image:', error);
    }
  };

  const openImageInNewTab = (image: GeneratedImage) => {
    try {
      const imageUrl = image.gcs_url || `data:image/${image.format};base64,${image.base64}`;
      const newTab = window.open();
      if (newTab) {
        newTab.document.write(`
          <html>
            <head><title>Story Keyframe</title></head>
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

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <h3 className="text-xl font-semibold text-gray-800 dark:text-gray-200">
          Story Keyframes
        </h3>
        {isGenerating && (
          <div className="flex items-center gap-2 text-sm text-blue-600 dark:text-blue-400">
            <Loader2 className="h-4 w-4 animate-spin" />
            <span>Generating images...</span>
          </div>
        )}
      </div>

      {generationStatus && !isGenerating && (
        <div className="text-sm text-gray-600 dark:text-gray-400 bg-gray-100 dark:bg-gray-800 rounded-lg p-3">
          {generationStatus}
        </div>
      )}
      
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        {/* Display generated images */}
        {displayImages.map((image, index) => (
          <div 
            key={`generated-${index}`}
            className="group aspect-video bg-gray-200 dark:bg-gray-700 rounded-xl shadow-md overflow-hidden relative"
          >
            <img
              src={image.gcs_url ? image.gcs_url : `data:image/${image.format};base64,${image.base64}`}
              alt={`Generated keyframe ${index + 1}`}
              className="w-full h-full object-cover"
              onError={(e) => {
                // Fallback to placeholder if image fails to load
                const target = e.target as HTMLImageElement;
                target.style.display = 'none';
                target.parentElement!.innerHTML = `
                  <div class="flex items-center justify-center h-full text-gray-500">
                    <div class="text-center">
                      <div class="text-2xl mb-2">🖼️</div>
                      <div class="text-sm">Image ${index + 1}</div>
                    </div>
                  </div>
                `;
              }}
            />
            
            {/* Image overlay controls */}
            <div className="absolute inset-0 bg-black bg-opacity-0 group-hover:bg-opacity-30 transition-all duration-200 flex items-center justify-center opacity-0 group-hover:opacity-100">
              <div className="flex gap-2">
                <button
                  onClick={() => openImageInNewTab(image)}
                  className="p-2 bg-white bg-opacity-20 hover:bg-opacity-30 rounded-full transition-all"
                  title="View full size"
                >
                  <Eye className="h-4 w-4 text-white" />
                </button>
                <button
                  onClick={() => downloadImage(image, index)}
                  className="p-2 bg-white bg-opacity-20 hover:bg-opacity-30 rounded-full transition-all"
                  title="Download image"
                >
                  <Download className="h-4 w-4 text-white" />
                </button>
              </div>
            </div>
            
            {/* Image index */}
            <div className="absolute bottom-2 left-2 bg-black bg-opacity-50 text-white text-xs px-2 py-1 rounded">
              {index + 1}
            </div>
          </div>
        ))}

        {/* Fill remaining slots with generating placeholders or fallback placeholders */}
        {Array.from({ length: Math.max(0, 4 - displayImages.length) }).map((_, index) => (
          <div 
            key={`placeholder-${displayImages.length + index}`}
            className="aspect-video bg-gray-200 dark:bg-gray-700 rounded-xl flex items-center justify-center shadow-md overflow-hidden"
          >
            {isGenerating ? (
              <div className="text-center p-4">
                <Loader2 className="h-6 w-6 text-gray-500 dark:text-gray-400 animate-spin mx-auto mb-2" />
                <p className="text-sm text-gray-500 dark:text-gray-400">
                  Generating...
                </p>
              </div>
            ) : showPlaceholders ? (
              <div className="text-center p-4">
                <p className="font-medium text-gray-600 dark:text-gray-300">
                  {fallbackKeyframes[displayImages.length + index]?.title || `Frame ${displayImages.length + index + 1}`}
                </p>
                <p className="text-sm text-gray-500 dark:text-gray-400">
                  Image {displayImages.length + index + 1}
                </p>
              </div>
            ) : (
              <div className="text-center p-4">
                <p className="text-sm text-gray-500 dark:text-gray-400">
                  Image {displayImages.length + index + 1}
                </p>
              </div>
            )}
          </div>
        ))}
      </div>

      {images.length > 0 && (
        <div className="text-sm text-gray-600 dark:text-gray-400 text-center">
          Generated {images.length} of 4 keyframes • Hover over images to download or view full size
        </div>
      )}
    </div>
  );
}
