import { BookOpen, Loader2, Volume2, VolumeX, Play, Pause } from 'lucide-react';
import { useState, useEffect, useRef } from 'react';

interface StoryCardProps {
  story: string;
  title?: string;
  isLoading?: boolean;
  isGenerating?: boolean;
}

export default function StoryCard({ 
  story, 
  title = "Your Generated Story", 
  isLoading = false,
  isGenerating = false 
}: StoryCardProps) {
  const [isReading, setIsReading] = useState(false);
  const [isPaused, setIsPaused] = useState(false);
  const [isSupported, setIsSupported] = useState(false);
  const utteranceRef = useRef<SpeechSynthesisUtterance | null>(null);

  useEffect(() => {
    // Check if text-to-speech is supported
    if (typeof window !== 'undefined' && 'speechSynthesis' in window) {
      setIsSupported(true);
    }

    // Cleanup on unmount
    return () => {
      if (utteranceRef.current) {
        window.speechSynthesis.cancel();
      }
    };
  }, []);

  const handleReadStory = () => {
    if (!isSupported || !story.trim()) return;

    if (isReading) {
      if (isPaused) {
        // Resume reading
        window.speechSynthesis.resume();
        setIsPaused(false);
      } else {
        // Pause reading
        window.speechSynthesis.pause();
        setIsPaused(true);
      }
      return;
    }

    // Start reading
    const utterance = new SpeechSynthesisUtterance(story);
    utteranceRef.current = utterance;

    // Configure speech settings
    utterance.rate = 0.9; // Slightly slower than normal
    utterance.pitch = 1.0;
    utterance.volume = 0.8;

    // Try to use a pleasant voice
    const voices = window.speechSynthesis.getVoices();
    const preferredVoice = voices.find(voice => 
      voice.name.includes('Samantha') || 
      voice.name.includes('Alex') || 
      voice.name.includes('Daniel') ||
      voice.lang.startsWith('en')
    );
    if (preferredVoice) {
      utterance.voice = preferredVoice;
    }

    utterance.onstart = () => {
      setIsReading(true);
      setIsPaused(false);
    };

    utterance.onend = () => {
      setIsReading(false);
      setIsPaused(false);
      utteranceRef.current = null;
    };

    utterance.onerror = () => {
      setIsReading(false);
      setIsPaused(false);
      utteranceRef.current = null;
    };

    utterance.onpause = () => {
      setIsPaused(true);
    };

    utterance.onresume = () => {
      setIsPaused(false);
    };

    window.speechSynthesis.speak(utterance);
  };

  const handleStopReading = () => {
    window.speechSynthesis.cancel();
    setIsReading(false);
    setIsPaused(false);
    utteranceRef.current = null;
  };

  const getReadButtonIcon = () => {
    if (!isReading) return <Volume2 className="h-4 w-4" />;
    if (isPaused) return <Play className="h-4 w-4" />;
    return <Pause className="h-4 w-4" />;
  };

  const getReadButtonText = () => {
    if (!isReading) return "Read Story";
    if (isPaused) return "Resume";
    return "Pause";
  };

  return (
    <div className="bg-white dark:bg-gray-800 rounded-3xl shadow-lg p-8 transition-all">
      <div className="flex items-center gap-3 mb-6">
        <BookOpen className="h-6 w-6 text-purple-600" />
        <h2 className="text-2xl font-bold text-gray-900 dark:text-white flex-1">
          {title}
        </h2>
        
        {/* Text-to-Speech Controls */}
        {isSupported && story && !isLoading && (
          <div className="flex gap-2">
            <button
              onClick={handleReadStory}
              disabled={isGenerating || !story.trim()}
              className="flex items-center gap-2 px-3 py-2 text-sm font-medium text-purple-600 dark:text-purple-400 bg-purple-50 dark:bg-purple-900/20 rounded-lg hover:bg-purple-100 dark:hover:bg-purple-900/30 transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
              aria-label={getReadButtonText()}
            >
              {getReadButtonIcon()}
              <span className="hidden sm:inline">{getReadButtonText()}</span>
            </button>
            
            {isReading && (
              <button
                onClick={handleStopReading}
                className="flex items-center gap-2 px-3 py-2 text-sm font-medium text-red-600 dark:text-red-400 bg-red-50 dark:bg-red-900/20 rounded-lg hover:bg-red-100 dark:hover:bg-red-900/30 transition-colors"
                aria-label="Stop reading"
              >
                <VolumeX className="h-4 w-4" />
                <span className="hidden sm:inline">Stop</span>
              </button>
            )}
          </div>
        )}
        
        {isGenerating && (
          <Loader2 className="h-5 w-5 text-purple-600 animate-spin" />
        )}
      </div>
      
      <div className="prose dark:prose-invert max-w-none">
        {isLoading ? (
          <div className="flex items-center justify-center py-12">
            <Loader2 className="h-8 w-8 text-purple-600 animate-spin" />
            <span className="ml-3 text-gray-600 dark:text-gray-400">
              Connecting to story generator...
            </span>
          </div>
        ) : story ? (
          <div className="text-gray-700 dark:text-gray-300 leading-relaxed whitespace-pre-wrap">
            {story}
          </div>
        ) : (
          <div className="text-gray-500 dark:text-gray-400 italic py-8 text-center">
            Your generated story will appear here...
          </div>
        )}
        
        {isGenerating && story && (
          <div className="mt-4 flex items-center text-sm text-purple-600 dark:text-purple-400">
            <Loader2 className="h-4 w-4 animate-spin mr-2" />
            Generating story...
          </div>
        )}

        {/* Reading Status Indicator */}
        {isReading && (
          <div className="mt-4 flex items-center text-sm text-blue-600 dark:text-blue-400">
            {isPaused ? (
              <>
                <Pause className="h-4 w-4 mr-2" />
                Reading paused - click Resume to continue
              </>
            ) : (
              <>
                <Volume2 className="h-4 w-4 animate-pulse mr-2" />
                Currently reading story aloud...
              </>
            )}
          </div>
        )}
      </div>
    </div>
  );
}
