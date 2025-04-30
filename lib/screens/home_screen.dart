import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:iconsax/iconsax.dart';
import 'package:quotes/screens/drawer.dart';
import 'package:quotes/services/constants.dart';
import 'package:quotes/services/user_controls.dart';
import 'package:quotes/services/user_service.dart';
import "package:http/http.dart" as http;
import 'package:sensors_plus/sensors_plus.dart';
import 'package:share_plus/share_plus.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, Key? keyy});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  String todaysQuote = '';
  bool isLiked = false;
  bool isLoading = false;
  List<String> favoriteQuotes = [];
  String currentImage = "";
  int imageCounter = 1;
  final UserService _userService = UserService();

  late final Ticker _ticker;
  late StreamSubscription<AccelerometerEvent> _accelerometerStream;
  final ValueNotifier<Offset> _imageOffset = ValueNotifier(Offset.zero);
  Offset _targetOffset = Offset.zero;

  // ============ TUNING VARIABLES ============

  // Controls how fast the image follows the tilt (higher = faster/less smooth)
  double _smoothingFactor = 0.15;

  // Controls how much the image shifts with phone tilt (higher = faster movement)
  static const double _sensitivity = 25.0;

  // Maximum offset allowed in any direction (higher = bigger visual shift)
  static const double _maxOffset = 50.0;

  // ==========================================

  @override
  void initState() {
    super.initState();
    refreshQuote();
    _startAccelerometer();

    _ticker = createTicker((_) {
      final dx =
          lerpDouble(
            _imageOffset.value.dx,
            _targetOffset.dx,
            _smoothingFactor,
          )!;
      final dy =
          lerpDouble(
            _imageOffset.value.dy,
            _targetOffset.dy,
            _smoothingFactor,
          )!;
      _imageOffset.value = Offset(dx, dy);
    });

    _ticker.start();
  }

  void _startAccelerometer() {
    _accelerometerStream = accelerometerEvents.listen((
      AccelerometerEvent event,
    ) {
      final double targetX = (-event.x * _sensitivity).clamp(
        -_maxOffset,
        _maxOffset,
      );
      final double targetY = (event.y * _sensitivity).clamp(
        -_maxOffset,
        _maxOffset,
      );
      _targetOffset = Offset(targetX, targetY);
    });
  }

  Future<void> refreshQuote() async {
    setState(() {
      isLoading = true;
    });

    try {
      final r = await http.get(
        Uri.parse("$unsplashEndpoint&page=$imageCounter&per_page=1"),
      );
      final data = jsonDecode(r.body);
      currentImage = data['results'][0]['urls']['regular'];

      final Map<String, String> quoteData = await _userService.getSingleQuote();

      if (quoteData.isNotEmpty) {
        final String quote = quoteData['quote']!;
        final String author = quoteData['author']!;
        todaysQuote = '$quote\n- $author';
        isLiked = false;
      } else {
        throw Exception('Quote data is empty');
      }

      imageCounter++;
    } catch (e) {
      todaysQuote = 'Failed to fetch quote';
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  void addToFavorites(String quote) {
    setState(() {
      favoriteQuotes.add(quote);
    });
  }

  void removeFromFavorites(int index) {
    if (favoriteQuotes.isNotEmpty &&
        index >= 0 &&
        index < favoriteQuotes.length) {
      favoriteQuotes.removeAt(index);
    }
    setState(() {});
  }

  void shareQuote(String quote) {
    SharePlus.instance.share(quote as ShareParams);
  }

  void resetLikeButton() {
    setState(() {
      isLiked = false;
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    _accelerometerStream.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      drawer: MyDrawer(
        favoriteQuotes: favoriteQuotes,
        addToFavoritesCallback: (quote) {
          addToFavorites(quote);
        },
        removeFromFavorites: (index) {
          removeFromFavorites(index);
        },
      ),
      body: Stack(
        children: [
          if (currentImage != "")
            ValueListenableBuilder<Offset>(
              valueListenable: _imageOffset,
              builder: (context, offset, child) {
                return Transform.translate(
                  offset: offset,
                  child: OverflowBox(
                    maxWidth: MediaQuery.of(context).size.width * 1.3,
                    maxHeight: MediaQuery.of(context).size.height * 1.3,
                    alignment: Alignment.center,
                    child: Image.network(
                      currentImage,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                    ),
                  ),
                );
              },
            ),
          if (currentImage != "")
            Container(
              height: double.infinity,
              decoration: BoxDecoration(
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.5)),
                ],
              ),
            ),

          // Menu button
          SafeArea(
            child: Builder(
              builder: (context) {
                return Align(
                  alignment: Alignment.topLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 10),
                    child: IconButton(
                      icon: const Icon(Iconsax.menu, color: Colors.white),
                      onPressed: () {
                        Scaffold.of(context).openDrawer();
                      },
                    ),
                  ),
                );
              },
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 250, left: 16, right: 16),
                child: SingleChildScrollView(
                  child: Text(
                    todaysQuote,
                    style: const TextStyle(fontSize: 18, color: Colors.white),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              const Spacer(),
              UserControls(
                isLiked: isLiked,
                onTapLike: (isCurrentlyLiked) {
                  setState(() {
                    if (isCurrentlyLiked) {
                      removeFromFavorites(favoriteQuotes.indexOf(todaysQuote));
                    } else {
                      addToFavorites(todaysQuote);
                    }
                    isLiked = !isCurrentlyLiked;
                  });
                },
                onRefresh: refreshQuote,
                onShare: () {
                  shareQuote(todaysQuote);
                },
              ),
            ],
          ),
          if (isLoading)
            const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
        ],
      ),
    );
  }
}
