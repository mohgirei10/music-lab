// ignore_for_file: deprecated_member_use

import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => PlayerProvider(),
      child: const TrapHouseApp(),
    ),
  );
}

class TrapHouseApp extends StatelessWidget {
  const TrapHouseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'THE MUSIC LAB',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0A0A0A),
        primaryColor: Colors.white,
        colorScheme: const ColorScheme.dark(
          primary: Colors.white,
          secondary: Colors.white70,
        ),
      ),
      home: const MainShell(),
    );
  }
}

// --- DATA MODELS ---
enum SearchType { song, album, artist, playlist }

class MediaItem {
  final String id;
  final String title;
  final String subtitle;
  final String image;
  final SearchType type;

  const MediaItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.image,
    required this.type,
  });
}

// --- STATE MANAGEMENT ---
class PlayerProvider extends ChangeNotifier {
  YoutubePlayerController? _controller;
  
  // Replace with your restricted YouTube Data API v3 Key
  final String _apiKey = "AIzaSyDIJq6yn_5GFUSmDFPGWBwv4AwtM5WQUmQ"; 

  List<MediaItem> songs = [];
  List<MediaItem> albums = [];
  List<MediaItem> artists = [];
  List<MediaItem> playlists = [];

  int currentIndex = 0;
  bool isSearching = false;

  MediaItem? get currentTrack => songs.isNotEmpty ? songs[currentIndex] : null;
  
  // We check the controller's value directly to ensure the UI updates accurately
  bool get isPlaying => _controller?.value.playerState == PlayerState.playing;

  /// Global search function for all types
  Future<void> search(String query, SearchType type) async {
    if (query.trim().isEmpty) return;
    isSearching = true;
    notifyListeners();

    String ytType = 'video';
    String q = query;

    // Tailor the search query based on category
    switch (type) {
      case SearchType.song:
        ytType = 'video';
        q = "$query official audio";
        break;
      case SearchType.artist:
        ytType = 'channel';
        break;
      case SearchType.album:
        ytType = 'playlist';
        q = "$query full album";
        break;
      case SearchType.playlist:
        ytType = 'playlist';
        break;
    }

    try {
      final url = Uri.parse(
        'https://www.googleapis.com/youtube/v3/search?'
        'part=snippet&q=${Uri.encodeComponent(q)}'
        '&type=$ytType&maxResults=15&key=$_apiKey',
      );

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final items = data['items'] as List;

        final results = items.map((item) {
          final snippet = item['snippet'];
          final idObj = item['id'];
          String id = idObj['videoId'] ?? idObj['channelId'] ?? idObj['playlistId'] ?? "";

          return MediaItem(
            id: id,
            title: snippet['title'] ?? 'Unknown',
            subtitle: snippet['channelTitle'] ?? '',
            image: snippet['thumbnails']['high']['url'] ?? '',
            type: type,
          );
        }).toList();

        if (type == SearchType.song) {
          songs = results;
        // ignore: curly_braces_in_flow_control_structures
        } else if (type == SearchType.artist) artists = results;
        // ignore: curly_braces_in_flow_control_structures
        else if (type == SearchType.album) albums = results;
        // ignore: curly_braces_in_flow_control_structures
        else if (type == SearchType.playlist) playlists = results;
      }
    } catch (e) {
      debugPrint("Search Error: $e");
    }

    isSearching = false;
    notifyListeners();
  }

  /// Special function to fetch tracks from a specific Playlist or Album
  Future<void> fetchPlaylistTracks(String playlistId) async {
    isSearching = true;
    notifyListeners();

    try {
      final url = Uri.parse(
        'https://www.googleapis.com/youtube/v3/playlistItems?'
        'part=snippet&playlistId=$playlistId&maxResults=25&key=$_apiKey',
      );

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final items = data['items'] as List;

        songs = items.map((item) {
          final snippet = item['snippet'];
          return MediaItem(
            id: snippet['resourceId']['videoId'],
            title: snippet['title'],
            subtitle: snippet['channelTitle'],
            image: snippet['thumbnails']['high']['url'],
            type: SearchType.song,
          );
        }).toList();
      }
    } catch (e) {
      debugPrint("Playlist Error: $e");
    }

    isSearching = false;
    notifyListeners();
  }

  void playTrack(int index) {
    currentIndex = index;
    if (_controller != null) {
      _controller!.loadVideoById(videoId: songs[index].id);
    }
    notifyListeners();
  }

  void togglePlay() {
    if (_controller == null) return;
    isPlaying ? _controller!.pauseVideo() : _controller!.playVideo();
    notifyListeners();
  }

  void setController(YoutubePlayerController controller) {
    _controller = controller;
    _controller!.listen((state) {
      notifyListeners();
    });
  }
}

// --- UI SHELL ---
class MainShell extends StatelessWidget {
  const MainShell({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Stack(
        children: [
          HomeScreen(),
          Align(
            alignment: Alignment.bottomCenter,
            child: MiniPlayer(),
          ),
        ],
      ),
    );
  }
}

// --- HOME SCREEN ---
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    
    // Auto-refresh data when user taps a different tab
    _tabController.addListener(() {
      if (_tabController.indexIsChanging && _searchController.text.isNotEmpty) {
        context.read<PlayerProvider>().search(
          _searchController.text, 
          SearchType.values[_tabController.index],
        );
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PlayerProvider>();

    return CustomScrollView(
      slivers: [
        const SliverAppBar(
          backgroundColor: Color(0xFF0A0A0A),
          floating: true,
          pinned: true,
          elevation: 0,
          title: Text("THE LAB", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 24)),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: TextField(
              controller: _searchController,
              onSubmitted: (val) => provider.search(val, SearchType.values[_tabController.index]),
              decoration: InputDecoration(
                hintText: "Artists, songs, or playlists...",
                prefixIcon: const Icon(Icons.search, color: Colors.white70),
                filled: true,
                fillColor: const Color(0xFF1A1A1A),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: TabBar(
            controller: _tabController,
            isScrollable: true,
            indicatorColor: Colors.white,
            labelStyle: const TextStyle(fontWeight: FontWeight.bold),
            unselectedLabelColor: Colors.grey,
            tabs: const [
              Tab(text: "Songs"),
              Tab(text: "Albums"),
              Tab(text: "Artists"),
              Tab(text: "Playlists"),
            ],
          ),
        ),
        SliverFillRemaining(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildGrid(provider.songs, isArtist: false),
              _buildGrid(provider.albums, isArtist: false),
              _buildGrid(provider.artists, isArtist: true),
              _buildGrid(provider.playlists, isArtist: false),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGrid(List<MediaItem> items, {required bool isArtist}) {
    final provider = context.read<PlayerProvider>();
    
    if (provider.isSearching) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    
    if (items.isEmpty) {
      return const Center(child: Text("Start searching for heat...", style: TextStyle(color: Colors.grey)));
    }

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: isArtist ? 3 : 2,
        mainAxisSpacing: 24,
        crossAxisSpacing: 16,
        childAspectRatio: isArtist ? 0.8 : 0.72,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return GestureDetector(
          onTap: () async {
            if (item.type == SearchType.song) {
              provider.playTrack(index);
              _openPlayer(context, item);
            } else if (item.type == SearchType.artist) {
              _searchController.text = item.title;
              await provider.search(item.title, SearchType.song);
              _tabController.animateTo(0);
            } else {
              // Albums and Playlists
              await provider.fetchPlaylistTracks(item.id);
              _tabController.animateTo(0);
            }
          },
          child: Column(
            crossAxisAlignment: isArtist ? CrossAxisAlignment.center : CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    shape: isArtist ? BoxShape.circle : BoxShape.rectangle,
                    borderRadius: isArtist ? null : BorderRadius.circular(12),
                    image: DecorationImage(image: NetworkImage(item.image), fit: BoxFit.cover),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: isArtist ? TextAlign.center : TextAlign.start,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              if (!isArtist)
                Text(
                  item.subtitle,
                  maxLines: 1,
                  style: const TextStyle(color: Colors.grey, fontSize: 11),
                ),
            ],
          ),
        );
      },
    );
  }

  void _openPlayer(BuildContext context, MediaItem track) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => FullscreenPlayer(track: track),
    );
  }
}

// --- MINI PLAYER ---
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PlayerProvider>();
    final track = provider.currentTrack;

    if (track == null) return const SizedBox.shrink();

    return GestureDetector(
      onTap: () => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => FullscreenPlayer(track: track),
      ),
      child: Container(
        height: 72,
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 24),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white10),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(track.image, width: 48, height: 48, fit: BoxFit.cover),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text(track.subtitle, maxLines: 1, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
            ),
            IconButton(
              icon: Icon(provider.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 32),
              onPressed: provider.togglePlay,
            ),
          ],
        ),
      ),
    );
  }
}

// --- FULLSCREEN PLAYER ---
class FullscreenPlayer extends StatefulWidget {
  final MediaItem track;
  const FullscreenPlayer({super.key, required this.track});

  @override
  State<FullscreenPlayer> createState() => _FullscreenPlayerState();
}

class _FullscreenPlayerState extends State<FullscreenPlayer> {
  late YoutubePlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = YoutubePlayerController.fromVideoId(
      videoId: widget.track.id,
      params: const YoutubePlayerParams(
        showControls: true,
        showFullscreenButton: true,
        mute: false,
      ),
    );
    
    // Connect to provider after first build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PlayerProvider>().setController(_controller);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Background Blur
          Positioned.fill(
            child: Image.network(widget.track.image, fit: BoxFit.cover),
          ),
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
              child: Container(color: Colors.black.withOpacity(0.65)),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 8),
                IconButton(
                  icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 40),
                  onPressed: () => Navigator.pop(context),
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: YoutubePlayer(controller: _controller),
                    ),
                  ),
                ),
                const SizedBox(height: 48),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    children: [
                      Text(
                        widget.track.title,
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.track.subtitle,
                        style: const TextStyle(fontSize: 18, color: Colors.white70),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                const Spacer(flex: 2),
              ],
            ),
          ),
        ],
      ),
    );
  }
}