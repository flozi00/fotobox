# fotobox

# PhotoBox Flutter App

A Flutter application designed for photobox functionality that allows users to:
- Take photos using the device camera
- Select photos from the gallery
- Choose background images
- Send images to an API for processing
- Display the processed result

## Features

- **Camera Integration**: Take photos directly from the app
- **Gallery Access**: Select existing photos from device gallery
- **Background Selection**: Choose custom background images
- **API Processing**: Send images to a backend API for processing
- **Real-time Preview**: Live camera preview and image display
- **Modern UI**: Clean, intuitive Material Design 3 interface

## Setup Instructions

### 1. Install Dependencies
```bash
flutter pub get
```

### 2. Configure API Endpoint
Edit `lib/main.dart` and replace the placeholder API URL with your actual endpoint:
```dart
Uri.parse('https://your-api-endpoint.com/process-image')
```

### 3. Run the App
```bash
flutter run
```

## Permissions

The app requires the following permissions:
- **Camera**: To capture photos
- **Storage**: To save and access images
- **Internet**: To communicate with the API

These permissions are automatically handled on Android. For iOS, additional Info.plist configuration may be required.

## Project Structure

```
lib/
  main.dart                 # Main application code
assets/
  backgrounds/              # Background images directory
android/
  app/src/main/
    AndroidManifest.xml     # Android permissions configuration
```

## API Integration

See `API_INTEGRATION.md` for detailed information about:
- API endpoint configuration
- Request/response format
- Authentication setup
- Error handling
- Testing without a backend

## Dependencies

- `camera`: Camera functionality
- `image_picker`: Gallery access
- `file_picker`: File selection
- `permission_handler`: Runtime permissions
- `http`: API communication
- `path_provider`: File system access

## Development Notes

- The app is designed to work on both Android and iOS
- Camera preview and capture functionality is built-in
- Background image selection supports various image formats
- API communication uses multipart form data
- Error handling includes network and permission issues

## Next Steps

1. Replace the placeholder API endpoint with your actual backend
2. Test the complete workflow with your image processing API
3. Customize the UI/UX as needed
4. Add additional features like image filters or editing tools
5. Implement local image saving for processed results

For detailed API integration instructions, see `API_INTEGRATION.md`.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
