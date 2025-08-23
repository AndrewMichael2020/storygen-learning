"use client";

import { useState, useEffect, useRef, useCallback } from "react";
import { Moon, Sun, Mic, MicOff, Wifi, WifiOff } from 'lucide-react';
import { useTheme } from "next-themes";
import StoryFrames from "@/components/story-frames";

interface WebSocketMessage {
  type: string;
  data?: string;
  partial?: boolean;
  turn_complete?: boolean;
  interrupted?: boolean;
  message?: string;
}

interface GeneratedImage {
  index: number;
  base64?: string;
  gcs_url?: string;
  format: string;
  stored_in_bucket?: boolean;
  error?: string;
  placeholder?: boolean;
}

interface ImageGenerationData {
  success: boolean;
  prompt?: string;
  negative_prompt?: string;
  aspect_ratio?: string;
  images?: GeneratedImage[];
  error?: string;
}

// Interface for the image state array
type GeneratedImageState = (GeneratedImage | null)[];

export default function Home() {
  const [showStory, setShowStory] = useState(false);
  const { theme, setTheme } = useTheme();
  const [keywords, setKeywords] = useState("");
  const [isListening, setIsListening] = useState(false);
  const [recognition, setRecognition] = useState<any | null>(null);
  
  // WebSocket and story generation state
  const [isConnected, setIsConnected] = useState(false);
  const [isConnecting, setIsConnecting] = useState(false);
  const [story, setStory] = useState("");
  const [isGenerating, setIsGenerating] = useState(false);
  const [connectionError, setConnectionError] = useState<string | null>(null);
  
  // Image generation state
  const [generatedImages, setGeneratedImages] = useState<GeneratedImageState>([]);
  const [isGeneratingImages, setIsGeneratingImages] = useState(false);
  const [imageGenerationStatus, setImageGenerationStatus] = useState<string>("");
  
  const wsRef = useRef<WebSocket | null>(null);
  const reconnectTimeoutRef = useRef<NodeJS.Timeout | null>(null);
  const userIdRef = useRef<string>(Math.random().toString(36).substring(7));

  // WebSocket connection management
  const connectWebSocket = useCallback(() => {
    if (wsRef.current?.readyState === WebSocket.OPEN) {
      return; // Already connected
    }

    setIsConnecting(true);
    setConnectionError(null);

    try {
      // Use environment variable for the backend URL, with a fallback for local dev
      const wsBaseUrl = process.env.NEXT_PUBLIC_BACKEND_URL || 'ws://localhost:8000';
      const wsUrl = `${wsBaseUrl}/ws/${userIdRef.current}`;
      console.log(`Connecting to WebSocket at: ${wsUrl}`);
      const ws = new WebSocket(wsUrl);

      ws.onopen = () => {
        console.log('WebSocket connected');
        setIsConnected(true);
        setIsConnecting(false);
        setConnectionError(null);
        
        // Clear any existing reconnect timeout
        if (reconnectTimeoutRef.current) {
          clearTimeout(reconnectTimeoutRef.current);
          reconnectTimeoutRef.current = null;
        }
      };

      ws.onmessage = (event) => {
        try {
          const message: WebSocketMessage = JSON.parse(event.data);
          console.log('Received message:', message);

          switch (message.type) {
            case 'connected':
              console.log('Backend connection confirmed');
              break;

            case 'processing':
              setIsGenerating(true);
              setImageGenerationStatus(message.message || 'Generating...');
              break;

            case 'story_chunk':
              if (message.data) {
                if (message.partial) {
                  // Append to existing story
                  setStory(prev => prev + message.data);
                } else {
                  // Final chunk or complete story
                  setStory(prev => prev + message.data);
                }
              }
              break;

            case 'story_complete':
              if (message.data) {
                // Complete story received
                setStory(message.data);
                console.log('Complete story received:', message.data.length, 'characters');
              }
              break;

            case 'tool_call':
              // Handle tool call notifications
              const toolMessage = message as any;
              if (toolMessage.tool_name === 'generate_image') {
                setIsGeneratingImages(true);
                setImageGenerationStatus(`Generating image: ${toolMessage.parameters?.prompt || 'Unknown prompt'}`);
                console.log('Image generation started:', toolMessage.parameters);
              }
              break;

                          case 'image_generated':
              // Backend now may send either a full result object or a single image payload
              try {
                const payload: any = message.data;
                if (payload && Array.isArray(payload.images)) {
                  // Original shape with images array
                  setGeneratedImages(prev => [...prev, ...payload.images]);
                  setImageGenerationStatus('Generated image batch');
                  console.log('Image batch received:', payload);
                } else if (payload && (payload.gcs_url || payload.base64)) {
                  // Single image payload
                  const img: GeneratedImage = {
                    index: typeof payload.index === 'number' ? payload.index : (generatedImages.length % 4),
                    format: payload.format || 'png',
                    stored_in_bucket: payload.stored_in_bucket ?? !!payload.gcs_url,
                    ...(payload.gcs_url ? { gcs_url: payload.gcs_url } : {}),
                    ...(payload.base64 ? { base64: payload.base64 } : {})
                  };
                  
                  // Place the image at its specific index
                  setGeneratedImages(prev => {
                    const newImages = [...prev];
                    newImages[img.index] = img;
                    return newImages;
                  });
                  
                  setImageGenerationStatus(`Generated image ${img.index + 1} of 4`);
                  console.log('Single image received:', img);
                } else {
                  console.warn('Unknown image payload shape:', payload);
                }
              } catch (imageError) {
                console.error('Error processing image data:', imageError);
                setImageGenerationStatus('Error processing generated image');
              }
              break;

            case 'turn_complete':
              if (message.turn_complete) {
                setIsGenerating(false);
                setIsGeneratingImages(false);
                setImageGenerationStatus('');
                console.log('Story and image generation completed');
              }
              break;

            case 'error':
              console.error('Server error:', message.message);
              setConnectionError(message.message || 'Server error occurred');
              setIsGenerating(false);
              setIsGeneratingImages(false);
              setImageGenerationStatus('');
              break;

            case 'pong':
              // Handle ping/pong for keepalive
              break;

            default:
              console.log('Unknown message type:', message.type);
          }
        } catch (error) {
          console.error('Error parsing WebSocket message:', error);
        }
      };

      ws.onclose = (event) => {
        console.log('WebSocket disconnected:', event.code, event.reason);
        setIsConnected(false);
        setIsConnecting(false);
        setIsGenerating(false);
        setIsGeneratingImages(false);
        setImageGenerationStatus('');

        // Attempt to reconnect after 3 seconds if not manually closed
        if (event.code !== 1000 && !reconnectTimeoutRef.current) {
          reconnectTimeoutRef.current = setTimeout(() => {
            console.log('Attempting to reconnect...');
            connectWebSocket();
          }, 3000);
        }
      };

      ws.onerror = (error) => {
        console.error('WebSocket error:', error);
        setConnectionError('Failed to connect to story generation service');
        setIsConnecting(false);
        setIsGenerating(false);
        setIsGeneratingImages(false);
        setImageGenerationStatus('');
      };

      wsRef.current = ws;
    } catch (error) {
      console.error('Error creating WebSocket:', error);
      setConnectionError('Failed to create connection');
      setIsConnecting(false);
    }
  }, []);

  // Send message to WebSocket
  const sendMessage = useCallback((message: WebSocketMessage) => {
    if (wsRef.current?.readyState === WebSocket.OPEN) {
      wsRef.current.send(JSON.stringify(message));
      return true;
    } else {
      console.error('WebSocket not connected');
      setConnectionError('Not connected to story service');
      return false;
    }
  }, []);

  // Initialize WebSocket connection on component mount
  useEffect(() => {
    connectWebSocket();

    // Cleanup on unmount
    return () => {
      if (reconnectTimeoutRef.current) {
        clearTimeout(reconnectTimeoutRef.current);
      }
      if (wsRef.current) {
        wsRef.current.close(1000, 'Component unmounting');
      }
    };
  }, [connectWebSocket]);

  // Speech recognition setup (existing code)
  useEffect(() => {
    if (typeof window !== 'undefined' && 'webkitSpeechRecognition' in window) {
      const SpeechRecognition = window.webkitSpeechRecognition || window.SpeechRecognition;
      const recognitionInstance = new SpeechRecognition();
      
      recognitionInstance.continuous = false;
      recognitionInstance.interimResults = false;
      recognitionInstance.lang = 'en-US';
      
      recognitionInstance.onstart = () => {
        setIsListening(true);
      };
      
      recognitionInstance.onresult = (event: any) => {
        const transcript = event.results[0][0].transcript;
        setKeywords(prev => prev + (prev ? ' ' : '') + transcript);
      };
      
      recognitionInstance.onend = () => {
        setIsListening(false);
      };
      
      recognitionInstance.onerror = (event: any) => {
        console.error('Speech recognition error:', event.error);
        setIsListening(false);
      };
      
      setRecognition(recognitionInstance);
    }
  }, []);

  const handleGenerateStory = () => {
    if (!keywords.trim()) {
      alert('Please enter some keywords first!');
      return;
    }

    if (!isConnected) {
      setConnectionError('Not connected to story service. Attempting to reconnect...');
      connectWebSocket();
      return;
    }

    // Reset story and images, start generation
    setStory("");
    setGeneratedImages([]);
    setIsGenerating(true);
    setIsGeneratingImages(false);
    setImageGenerationStatus('');
    setShowStory(true);
    setConnectionError(null);

    // Initialize with 4 empty slots for the images
    setGeneratedImages(Array(4).fill(null));

    // Send story generation request
    const success = sendMessage({
      type: 'generate_story',
      data: keywords.trim()
    });

    if (!success) {
      setIsGenerating(false);
    }
  };

  const handleVoiceInput = () => {
    if (!recognition) {
      alert('Speech recognition is not supported in your browser');
      return;
    }
    
    if (isListening) {
      recognition.stop();
    } else {
      recognition.start();
    }
  };

  return (
    <div className="min-h-screen flex flex-col items-center px-4 py-8 md:py-16">
      {/* Dark Mode Toggle */}
      <div className="absolute top-4 right-4 flex items-center gap-3">
        {/* Connection Status Indicator */}
        <div className="flex items-center gap-2 px-3 py-1 rounded-full bg-gray-100 dark:bg-gray-800 text-sm">
          {isConnecting ? (
            <>
              <div className="w-2 h-2 bg-yellow-500 rounded-full animate-pulse"></div>
              <span className="text-yellow-600 dark:text-yellow-400">Connecting...</span>
            </>
          ) : isConnected ? (
            <>
              <div className="w-2 h-2 bg-green-500 rounded-full"></div>
              <span className="text-green-600 dark:text-green-400">Connected</span>
            </>
          ) : (
            <>
              <div className="w-2 h-2 bg-red-500 rounded-full"></div>
              <span className="text-red-600 dark:text-red-400">Disconnected</span>
            </>
          )}
        </div>
        
        <button
          onClick={() => setTheme(theme === "dark" ? "light" : "dark")}
          className="p-2 rounded-full bg-gray-100 dark:bg-gray-800 transition-colors"
          aria-label="Toggle theme"
        >
          {theme === "dark" ? (
            <Sun className="h-5 w-5 text-yellow-500" />
          ) : (
            <Moon className="h-5 w-5 text-gray-700" />
          )}
        </button>
      </div>

      {/* Hero Section */}
      <div className="w-full max-w-3xl mx-auto text-center space-y-8 mb-12">
        <h1 className="text-4xl md:text-5xl font-bold tracking-tight text-gray-900 dark:text-white">
          StoryGen
        </h1>
        <p className="text-xl text-gray-600 dark:text-gray-300">
          Enter keywords to generate a captivating story with AI-generated visuals
        </p>
        
        {/* Connection Error Display */}
        {connectionError && (
          <div className="bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 rounded-lg p-4">
            <p className="text-red-600 dark:text-red-400 text-sm">
              {connectionError}
            </p>
            <button
              onClick={connectWebSocket}
              className="mt-2 text-red-600 dark:text-red-400 hover:text-red-700 dark:hover:text-red-300 text-sm font-medium"
            >
              Try reconnecting
            </button>
          </div>
        )}

        {/* Image Generation Status */}
        {(isGeneratingImages || imageGenerationStatus) && (
          <div className="bg-blue-50 dark:bg-blue-900/20 border border-blue-200 dark:border-blue-800 rounded-lg p-4">
            <p className="text-blue-600 dark:text-blue-400 text-sm">
              {imageGenerationStatus || 'Generating images...'}
            </p>
          </div>
        )}
        
        <div className="flex flex-col md:flex-row gap-3 w-full max-w-2xl mx-auto">
          <div className="flex-1 relative">
            <input
              type="text"
              value={keywords}
              onChange={(e) => setKeywords(e.target.value)}
              placeholder="Enter keywords (e.g., hacker, AI, future)"
              className="w-full px-6 py-4 pr-14 text-lg rounded-2xl border border-gray-300 dark:border-gray-700 bg-white dark:bg-gray-800 shadow-sm focus:outline-none focus:ring-2 focus:ring-purple-500 dark:text-white"
              disabled={isGenerating}
              onKeyPress={(e) => {
                if (e.key === 'Enter' && !isGenerating) {
                  handleGenerateStory();
                }
              }}
            />
            <button
              onClick={handleVoiceInput}
              disabled={isGenerating}
              className={`absolute right-3 top-1/2 transform -translate-y-1/2 p-2 rounded-full transition-colors ${
                isListening 
                  ? 'bg-red-100 text-red-600 dark:bg-red-900 dark:text-red-400' 
                  : 'bg-gray-100 text-gray-600 dark:bg-gray-700 dark:text-gray-400 hover:bg-gray-200 dark:hover:bg-gray-600'
              } ${isGenerating ? 'opacity-50 cursor-not-allowed' : ''}`}
              aria-label={isListening ? 'Stop recording' : 'Start voice input'}
            >
              {isListening ? (
                <MicOff className="h-5 w-5" />
              ) : (
                <Mic className="h-5 w-5" />
              )}
            </button>
          </div>
          <button
            onClick={handleGenerateStory}
            disabled={isGenerating || !isConnected || !keywords.trim()}
            className="px-8 py-4 text-lg font-medium text-white bg-purple-600 rounded-2xl hover:bg-purple-700 focus:outline-none focus:ring-2 focus:ring-purple-500 focus:ring-offset-2 transition-colors shadow-md disabled:opacity-50 disabled:cursor-not-allowed"
          >
            {isGenerating ? 'Generating...' : 'Generate Story'}
          </button>
        </div>
      </div>

      {/* Story Display */}
      {showStory && (
        <div className="w-full max-w-5xl mx-auto space-y-12 animate-fade-in">
          <StoryFrames
            story={story}
            images={generatedImages}
            isGeneratingStory={isGenerating}
            isGeneratingImages={isGeneratingImages}
            generationStatus={imageGenerationStatus}
            expectedFrames={4}
          />
        </div>
      )}
    </div>
  );
}
