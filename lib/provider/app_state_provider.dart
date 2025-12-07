import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../repositories/anime_repositories.dart';
import '../services/firestore_service.dart';
import '../models/anime.dart';

class AppStateProvider extends ChangeNotifier {
  final AnimeRepository _repository = AnimeRepository();

  List<Anime> _animeList = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  String? _errorMessage;

  int _currentPage = 1;
  bool _hasMore = true;

  bool _isSearchMode = false;

  final FirestoreService _firestoreService = FirestoreService();
  StreamSubscription<List<Anime>>? _favoritesSubscription;

  List<Anime> _favorites = [];

  String _selectedGenre = "All";

  String _homeSearchQuery = "";
  String _favoriteSearchQuery = "";
  Timer? _searchDebounce;

  List<Anime> get animeList => _animeList;
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  String? get errorMessage => _errorMessage;
  bool get hasMore => _hasMore;
  int get currentPage => _currentPage;
  bool get isSearchMode => _isSearchMode;
  List<Anime> get favorites => _favorites;
  String get selectedGenre => _selectedGenre;
  String get homeSearchQuery => _homeSearchQuery;
  String get favoriteSearchQuery => _favoriteSearchQuery;

  AppStateProvider() {
    _initAuthListener();
    fetchTopAnime();
  }

  void _initAuthListener() {
    FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null) {
        _subscribeToFavorites(user.uid);
      } else {
        _unsubscribeFromFavorites();
      }
    });
  }

  void _subscribeToFavorites(String userId) {
    _favoritesSubscription?.cancel();
    _favoritesSubscription = _firestoreService.getFavoritesStream(userId).listen((favorites) {
      _favorites = favorites;
      notifyListeners();
    });
  }

  void _unsubscribeFromFavorites() {
    _favoritesSubscription?.cancel();
    _favorites = [];
    notifyListeners();
  }


  Future<void> fetchTopAnime({int page = 1}) async {
    _isLoading = true;
    _errorMessage = null;
    _isSearchMode = false;
    _currentPage = 1;
    _hasMore = true;
    notifyListeners();

    try {
      _animeList = await _repository.getTopAnime(page: page);
    } catch (e) {
      _errorMessage = 'Failed to load anime: $e';
      debugPrint('Error fetching anime: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadMoreAnime() async {
    if (_isLoadingMore || !_hasMore || _isSearchMode || _isLoading) return;

    _isLoadingMore = true;
    notifyListeners();

    try {
      _currentPage++;
      final newAnime = await _repository.getTopAnime(page: _currentPage);

      if (newAnime.isEmpty) {
        _hasMore = false;
        debugPrint('📄 No more anime to load (reached end)');
      } else {
        _animeList.addAll(newAnime);
        debugPrint('📄 Loaded page $_currentPage: ${newAnime.length} anime');
      }
    } catch (e) {
      _errorMessage = 'Failed to load more: $e';
      debugPrint('Error loading more anime: $e');
      _currentPage--;
    } finally {
      _isLoadingMore = false;
      notifyListeners();
    }
  }

  Future<void> searchAnimeFromAPI(String query) async {
    if (query.trim().isEmpty) {
      await fetchTopAnime();
      return;
    }

    _isLoading = true;
    _errorMessage = null;
    _isSearchMode = true;
    _hasMore = false;
    notifyListeners();

    try {
      _animeList = await _repository.searchAnime(query);
      debugPrint('🔍 Search results: ${_animeList.length} anime');
    } catch (e) {
      _errorMessage = 'Search failed: $e';
      debugPrint('Error searching anime: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<Anime?> getAnimeById(int malId) async {
    try {
      return await _repository.getAnimeById(malId);
    } catch (e) {
      debugPrint('Error fetching anime by ID: $e');
      return null;
    }
  }



  bool isFavorite(int malId) {
    return _favorites.any((anime) => anime.malId == malId);
  }

  void toggleFavorite(Anime anime) {
    if (isFavorite(anime.malId)) {
      removeFavorite(anime.malId);
    } else {
      addFavorite(anime);
    }
  }

  Future<void> addFavorite(Anime anime) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await _firestoreService.addFavorite(user.uid, anime);
    }
  }

  Future<void> removeFavorite(int malId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await _firestoreService.removeFavorite(user.uid, malId);
    }
  }

  int get favoritesCount => _favorites.length;

  void setSelectedGenre(String genre) {
    _selectedGenre = genre;
    notifyListeners();
  }

  void setHomeSearchQuery(String query) {
    _homeSearchQuery = query;
    notifyListeners();

    _searchDebounce?.cancel();

    _searchDebounce = Timer(const Duration(milliseconds: 800), () {
      if (query.trim().isNotEmpty) {
        searchAnimeFromAPI(query);
      } else {
        fetchTopAnime();
      }
    });
  }

  void setFavoriteSearchQuery(String query) {
    _favoriteSearchQuery = query;
    notifyListeners();
  }

  List<Anime> getFilteredAnimeForHome() {
    List<Anime> result = _animeList;

    if (_selectedGenre != "All") {
      result = result.where((anime) {
        return anime.genres.any(
                (genre) => genre.toLowerCase() == _selectedGenre.toLowerCase()
        );
      }).toList();
    }

    if (_homeSearchQuery.isNotEmpty) {
      result = result.where((anime) {
        return anime.title.toLowerCase().contains(_homeSearchQuery.toLowerCase());
      }).toList();
    }

    return result;
  }

  List<Anime> getFilteredFavorites() {
    List<Anime> result = _favorites;

    if (_favoriteSearchQuery.isNotEmpty) {
      result = result.where((anime) {
        return anime.title.toLowerCase().contains(_favoriteSearchQuery.toLowerCase());
      }).toList();
    }

    return result;
  }
}