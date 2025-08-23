# StoryGen - AI-Powered Children's Story Generator

A real-time story generation application that creates illustrated children's stories using AI. The app generates structured 4-scene stories with consistent character illustrations using Google's Gemini and Imagen models.

## Features

- **Real-time Story Generation**: Create stories from keywords using Google Gemini
- **Consistent Character Design**: AI-generated illustrations maintain character consistency across all scenes
- **4-Scene Structure**: Each story follows a classic narrative arc (Setup → Inciting Incident → Climax → Resolution)
- **WebSocket Communication**: Real-time updates between frontend and backend
- **Image Generation**: Automatic illustration generation using Google Imagen
- **Modern UI**: Beautiful, responsive interface built with Next.js and Tailwind CSS

## Architecture

- **Frontend**: Next.js 14 with TypeScript, Tailwind CSS, and WebSocket communication
- **Backend**: FastAPI with WebSocket support, Google ADK for AI agents
- **AI Models**: 
  - Story Generation: Google Gemini 1.5 Flash
  - Image Generation: Google Imagen via Vertex AI
- **Storage**: Google Cloud Storage for generated images

## Prerequisites

- **Docker and Docker Compose**: [Install here](https://docs.docker.com/get-docker/)
- **Google Cloud Account**: Required for Vertex AI (Imagen) and GCS.
- **Node.js and npm**: For frontend dependency management.

## 🚀 Local Development with Docker

This is the recommended way to run StoryGen locally. It uses Docker Compose to set up the frontend and backend services, ensuring a consistent and isolated development environment.

1.  **Configure Backend Environment**:
    -   Navigate to the `backend` directory.
    -   Create a `.env` file from the example: `cp env.example .env`
    -   Edit the `.env` file and add your Google Cloud credentials:
        ```env
        GOOGLE_CLOUD_PROJECT_ID="your-gcp-project-id"
        GOOGLE_APPLICATION_CREDENTIALS="/path/to/your/service-account.json"
        GENMEDIA_BUCKET="your-gcs-bucket-name"
        ```
    -   **Important**: Make sure the path to your service account JSON file is accessible from where you run Docker. A good practice is to place the key in a secure location and provide an absolute path.

2.  **Start the Application**:
    -   From the project's root directory, run:
        ```bash
        docker-compose up --build
        ```
    -   This command will:
        -   Build the Docker images for both the frontend and backend.
        -   Start both services.
        -   Enable hot-reloading, so your changes to the code are reflected instantly.

3.  **Access the Application**:
    -   **Frontend**: `http://localhost:3000`
    -   **Backend**: `http://localhost:8000`

4.  **Stopping the Application**:
    -   Press `Ctrl + C` in the terminal where `docker-compose` is running.
    -   To remove the containers, run `docker-compose down`.

## ☁️ Production Deployment

For deploying the application to a production environment, please refer to the instructions in `DEPLOYMENT.md`. This guide provides detailed steps for deploying to Google Cloud Run.

## Usage

1. Open the application in your browser
2. Enter keywords for your story (e.g., "cat eat fish")
3. Click "Generate Story"
4. Watch as the story and illustrations are generated in real-time
5. View the complete 4-scene story with consistent character illustrations

## Project Structure

```
storygen-main/
├── backend/
│   ├── main.py                 # FastAPI server with WebSocket endpoints
│   ├── story_agent/
│   │   ├── agent.py            # Story generation agent
│   │   ├── direct_image_agent.py # Image generation agent
│   │   └── imagen_tool_direct.py # Imagen integration
│   └── requirements.txt
├── frontend/
│   ├── app/                    # Next.js app directory
│   ├── components/             # React components
│   └── package.json
├── README.md
└── .gitignore
```

## API Endpoints

- `GET /health` - Health check
- `GET /` - API info
- `WebSocket /ws/{user_id}` - Real-time story generation

## Environment Variables

| Variable | Description | Required |
|----------|-------------|----------|
| `GOOGLE_CLOUD_PROJECT_ID` | Google Cloud Project ID | Yes |
| `GOOGLE_APPLICATION_CREDENTIALS` | Path to service account key | Yes |
| `GENMEDIA_BUCKET` | GCS bucket for image storage | Yes |

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- Google Gemini and Imagen for AI capabilities
- Next.js and FastAPI for the web framework
- Tailwind CSS for styling