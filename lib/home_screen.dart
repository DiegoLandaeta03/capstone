import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_service.dart';
import 'walkman_player_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  // List of screens for the 5 tabs
  final List<Widget> _screens = [
    const FeedScreen(),
    const ExploreScreen(),
    const CreateScreen(),
    const FriendsScreen(),
    const ProfileScreen(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      body: _screens[_selectedIndex],
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF16213E),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(25),
              blurRadius: 20,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _selectedIndex,
          onTap: _onItemTapped,
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.transparent,
          elevation: 0,
          selectedItemColor: Colors.blueAccent,
          unselectedItemColor: Colors.white38,
          selectedLabelStyle: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 12),
          unselectedLabelStyle: GoogleFonts.outfit(fontWeight: FontWeight.w400, fontSize: 12),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.music_video_rounded),
              label: 'Feed',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.search_rounded),
              label: 'Explore',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.add_circle_outline_rounded, size: 40, color: Colors.blueAccent),
              label: '',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.people_alt_rounded),
              label: 'Friends',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_rounded),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}

// 1. Reel style scrollable page
class FeedScreen extends StatelessWidget {
  const FeedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Demo data for now – you can wire this to Supabase later.
    final demoItems = List.generate(
      10,
      (i) => (
        title: 'Mixtape #${i + 1}',
        artist: '@creator_name',
        // Replace with a real URL or asset path when you hook up the backend.
        source: 'assets/audio/sample.mp3',
      ),
    );

    return PageView.builder(
      scrollDirection: Axis.vertical,
      itemCount: demoItems.length,
      itemBuilder: (context, index) {
        final item = demoItems[index];

        return Stack(
          fit: StackFit.expand,
          children: [
            // Background gradient to keep the TikTok-style feel.
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF000000),
                    Color(0xFF0A0A1A),
                    Color(0xFF1A1A2E),
                  ],
                ),
              ),
            ),

            // Centered cassette-style card similar to the Walkman screen.
            Center(
              child: _FeedCassetteCard(
                title: item.title,
                artist: item.artist,
                onTapPlay: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => WalkmanPlayerScreen(
                        filePath: item.source,
                        title: item.title,
                        artist: item.artist,
                      ),
                    ),
                  );
                },
              ),
            ),

            // Right Sidebar actions
            Positioned(
              right: 20,
              bottom: 100,
              child: Column(
                children: [
                  _actionButton(Icons.favorite_rounded, '12k'),
                  _actionButton(Icons.comment_rounded, '456'),
                  _actionButton(Icons.share_rounded, 'Share'),
                ],
              ),
            ),

            // Bottom Info
            Positioned(
              left: 20,
              bottom: 40,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '@creator_name',
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Check out this custom mix... #music #mixd',
                    style: GoogleFonts.outfit(color: Colors.white70),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _actionButton(IconData icon, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        children: [
          Icon(icon, size: 35, color: Colors.white70),
          const SizedBox(height: 5),
          Text(
            label,
            style: GoogleFonts.outfit(
              color: Colors.white70,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

/// Cassette-style card for the feed, visually aligned with the Walkman screen.
class _FeedCassetteCard extends StatelessWidget {
  const _FeedCassetteCard({
    required this.title,
    required this.artist,
    required this.onTapPlay,
  });

  final String title;
  final String artist;
  final VoidCallback onTapPlay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FractionallySizedBox(
      widthFactor: 0.9,
      heightFactor: 0.55,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFEEE8D5),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF4A4A4A), width: 3),
          boxShadow: const [
            BoxShadow(
              color: Colors.black38,
              blurRadius: 20,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(17),
          child: Column(
            children: [
              // Top label area (title + artist)
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(
                    bottom: BorderSide(color: Colors.black12, width: 1),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontSize: 18,
                        color: Colors.black87,
                        fontStyle: FontStyle.italic,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      artist,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontSize: 13,
                        color: Colors.black54,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),

              // Color stripe
              SizedBox(
                height: 16,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: const [
                    Expanded(
                      child: ColoredBox(color: Color(0xFFE57373)),
                    ),
                    Expanded(
                      child: ColoredBox(color: Color(0xFFFFB74D)),
                    ),
                    Expanded(
                      child: ColoredBox(color: Color(0xFF64B5F6)),
                    ),
                  ],
                ),
              ),

              // Middle area with reels + play button (static reels)
              Expanded(
                child: Container(
                  color: const Color(0xFFD5D0BC),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Center(child: _StaticReel()),
                      ),
                      GestureDetector(
                        onTap: onTapPlay,
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFF263238),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withAlpha(77),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.play_arrow_rounded,
                            size: 34,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const Expanded(
                        child: Center(child: _StaticReel()),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StaticReel extends StatelessWidget {
  const _StaticReel();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF263238),
        border: Border.all(color: Colors.white70, width: 2),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          for (int i = 0; i < 4; i++)
            Transform.rotate(
              angle: i * (3.1415926535 / 2),
              child: Container(
                width: 32,
                height: 3,
                color: Colors.white38,
              ),
            ),
          Container(
            width: 12,
            height: 12,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

// 2. Explore Page
class ExploreScreen extends StatelessWidget {
  const ExploreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            TextField(
              decoration: InputDecoration(
                hintText: 'Search mixers, artists, tracks...',
                hintStyle: GoogleFonts.outfit(color: Colors.white38),
                prefixIcon: const Icon(Icons.search, color: Colors.white38),
                filled: true,
                fillColor: const Color(0xFF16213E),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 30),
            Expanded(
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 15,
                  mainAxisSpacing: 15,
                  childAspectRatio: 1.5,
                ),
                itemCount: 6,
                itemBuilder: (context, index) {
                  final categories = ['Lo-Fi', 'Nightcore', 'Techno', 'Indie', 'Alternative', 'Hip Hop'];
                  return Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(15),
                      gradient: LinearGradient(
                        colors: [Colors.blueAccent.withAlpha(51), Colors.blueAccent.withAlpha(102)],
                      ),
                    ),
                    child: Center(
                      child: Text(
                        categories[index],
                        style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// 3. Plus/Create Page
class CreateScreen extends StatelessWidget {
  const CreateScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.add_circle_outline_rounded, size: 100, color: Colors.blueAccent),
          const SizedBox(height: 20),
          Text(
            'Create New Mix',
            style: GoogleFonts.outfit(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          Text('Upload tracks and mix your sound', style: GoogleFonts.outfit(color: Colors.white70)),
        ],
      ),
    );
  }
}

// 4. Friends Page
class FriendsScreen extends StatelessWidget {
  const FriendsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Text(
            'Friends',
            style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
          ),
          bottom: TabBar(
            indicatorColor: Colors.blueAccent,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white54,
            labelStyle: GoogleFonts.outfit(fontWeight: FontWeight.w600),
            tabs: const [
              Tab(text: 'Friends'),
              Tab(text: 'Mixes'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _FriendsTab(),
            _UserMixesTab(),
          ],
        ),
      ),
    );
  }
}

class _FriendsTab extends StatelessWidget {
  const _FriendsTab();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: 5,
      itemBuilder: (context, index) {
        return ListTile(
          leading: CircleAvatar(backgroundColor: Colors.blueAccent.withAlpha(128)),
          title: Text(
            'Friend Name ${index + 1}',
            style: GoogleFonts.outfit(color: Colors.white),
          ),
          subtitle: Text(
            'Last seen: 2 hrs ago',
            style: GoogleFonts.outfit(color: Colors.white38),
          ),
          trailing: const Icon(Icons.chat_bubble_outline, color: Colors.blueAccent),
        );
      },
    );
  }
}

class _MixTrack {
  const _MixTrack({
    required this.title,
    required this.artist,
    required this.source,
  });

  final String title;
  final String artist;
  final String source; // local path OR http(s) url
}

class _UserMixesTab extends StatelessWidget {
  const _UserMixesTab();

  static const _tracks = <_MixTrack>[
    _MixTrack(
      title: 'Walkman Demo Mix',
      artist: 'Ácido Pantera',
      source: 'assets/audio/sample.mp3',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Your Mixes',
          style: GoogleFonts.outfit(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        for (final t in _tracks)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF16213E),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white10),
            ),
            child: ListTile(
              leading: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.blueAccent.withAlpha(51),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.album_rounded, color: Colors.blueAccent),
              ),
              title: Text(t.title, style: GoogleFonts.outfit(color: Colors.white)),
              subtitle: Text(
                t.artist,
                style: GoogleFonts.outfit(color: Colors.white54),
              ),
              trailing: const Icon(Icons.play_arrow_rounded, color: Colors.white70),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => WalkmanPlayerScreen(
                      filePath: t.source,
                      title: t.title,
                      artist: t.artist,
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

// 5. Profile Page
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final AuthService authService = AuthService();
    final displayName = user?.userMetadata?['full_name'] ?? 'User';
    final photoUrl = user?.userMetadata?['avatar_url'] ?? 'https://via.placeholder.com/150';

    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 30),
            CircleAvatar(radius: 60, backgroundImage: NetworkImage(photoUrl)),
            const SizedBox(height: 20),
            Text(displayName, style: GoogleFonts.outfit(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
            Text(user?.email ?? '', style: GoogleFonts.outfit(color: Colors.white38)),
            const SizedBox(height: 30),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _stat('Mixes', '14'),
                _stat('Followers', '1.2k'),
                _stat('Following', '456'),
              ],
            ),
            const SizedBox(height: 40),
            _btn(Icons.edit_rounded, 'Edit Profile'),
            _btn(Icons.settings_rounded, 'Settings'),
            const SizedBox(height: 20),
            TextButton(
              onPressed: () => authService.signOut(),
              child: Text('LOGOUT', style: GoogleFonts.outfit(color: Colors.redAccent, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, String count) {
    return Column(
      children: [
        Text(count, style: GoogleFonts.outfit(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
        Text(label, style: GoogleFonts.outfit(color: Colors.white38)),
      ],
    );
  }

  Widget _btn(IconData icon, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 10),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF16213E),
          borderRadius: BorderRadius.circular(15),
        ),
        child: ListTile(
          leading: Icon(icon, color: Colors.blueAccent),
          title: Text(label, style: GoogleFonts.outfit(color: Colors.white)),
          trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Colors.white38),
        ),
      ),
    );
  }
}
