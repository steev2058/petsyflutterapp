import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'models/models.dart';
import 'screens/auth/auth_screens.dart';
import 'screens/community/community_screens.dart';
import 'screens/community/friends_activity_screen.dart';
import 'screens/community/friends_screens.dart';
import 'screens/community/user_profile_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/messages/message_screens.dart';
import 'screens/onboarding/onboarding_screens.dart';
import 'screens/pets/adoption_requests_screen.dart';
import 'screens/pets/add_guard_offer_screen.dart';
import 'screens/pets/admin_trainer_applications_screen.dart';
import 'screens/pets/apply_trainer_screen.dart';
import 'screens/pets/guard_dogs_screen.dart';
import 'screens/pets/health_screens.dart';
import 'screens/pets/lost_found_map_screen.dart';
import 'screens/pets/lost_found_screens.dart';
import 'screens/pets/pet_screens.dart';
import 'screens/pets/training_screens.dart';
import 'screens/profile/profile_screens.dart';
import 'screens/shell.dart';
import 'screens/shop/shop_screens.dart';
import 'screens/vets/vet_clinic_screen.dart';
import 'screens/vets/vet_screens.dart';
import 'state/app_state.dart';

const _protectedPrefixes = [
  '/my-pets',
  '/add-pet',
  '/guard-dogs/offer',
  '/training/apply',
  '/admin/trainer-applications',
  '/edit-pet',
  '/pet-health',
  '/appointments',
  '/vet/appointments',
  '/adoption-requests',
  '/favorites',
  '/book-appointment',
  '/orders',
  '/checkout',
  '/order-success',
  '/chat',
  '/notifications',
  '/edit-profile',
  '/create-post',
  '/friends',
  '/invite',
  '/lost-found/report',
  '/onboarding',
];

const _authRoutes = ['/login', '/signup', '/verify', '/forgot-password'];

/// Shared-axis vertical transition — same timing both ways across auth screens.
CustomTransitionPage<void> _authPage({
  required GoRouterState state,
  required Widget child,
}) {
  const duration = Duration(milliseconds: 400);
  return CustomTransitionPage<void>(
    key: state.pageKey,
    name: state.matchedLocation,
    child: child,
    transitionDuration: duration,
    reverseTransitionDuration: duration,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final enter = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      final leave = CurvedAnimation(
        parent: secondaryAnimation,
        curve: Curves.easeOutCubic,
      );

      return FadeTransition(
        opacity: Tween<double>(begin: 1, end: 0).animate(leave),
        child: SlideTransition(
          position: Tween<Offset>(begin: Offset.zero, end: const Offset(0, -0.024)).animate(leave),
          child: FadeTransition(
            opacity: enter,
            child: SlideTransition(
              position: Tween<Offset>(begin: const Offset(0, 0.03), end: Offset.zero).animate(enter),
              child: child,
            ),
          ),
        ),
      );
    },
  );
}

GoRouter buildRouter(AuthState auth) {
  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: auth,
    redirect: (context, state) {
      final path = state.matchedLocation;
      // Splash owns its exit after the branded intro; stay put until it navigates.
      if (path == '/splash') return null;
      if (!auth.isReady) return '/splash';
      if (auth.isLoggedIn && _authRoutes.contains(path)) return '/home';
      if (!auth.isLoggedIn && _protectedPrefixes.any(path.startsWith)) return '/login';
      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        pageBuilder: (_, state) => CustomTransitionPage<void>(
          key: state.pageKey,
          name: state.matchedLocation,
          child: const SplashScreen(),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: const Duration(milliseconds: 420),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(
              opacity: Tween<double>(begin: 1, end: 0).animate(
                CurvedAnimation(parent: secondaryAnimation, curve: Curves.easeOut),
              ),
              child: child,
            );
          },
        ),
      ),
      GoRoute(
        path: '/login',
        pageBuilder: (_, state) => _authPage(state: state, child: const LoginScreen()),
      ),
      GoRoute(
        path: '/signup',
        pageBuilder: (_, state) => _authPage(state: state, child: const SignupScreen()),
      ),
      GoRoute(
        path: '/verify',
        pageBuilder: (_, state) => _authPage(
          state: state,
          child: VerifyScreen(args: state.extra! as VerifyArgs),
        ),
      ),
      GoRoute(
        path: '/forgot-password',
        pageBuilder: (_, state) => _authPage(state: state, child: const ForgotPasswordScreen()),
      ),
      GoRoute(
        path: '/onboarding',
        pageBuilder: (_, state) => _authPage(state: state, child: const OnboardingWelcomeScreen()),
      ),
      GoRoute(
        path: '/onboarding/pet',
        pageBuilder: (_, state) => _authPage(state: state, child: const OnboardingAddPetScreen()),
      ),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => MainShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/home', builder: (_, _) => const HomeScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/adoption', builder: (_, _) => const AdoptionScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/shop', builder: (_, _) => const ShopScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/messages', builder: (_, _) => const ConversationsScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen())]),
        ],
      ),
      GoRoute(path: '/pet/:id', builder: (_, s) => PetDetailScreen(petId: s.pathParameters['id']!)),
      GoRoute(path: '/guard-dogs', builder: (_, _) => const GuardDogsScreen()),
      GoRoute(path: '/guard-dogs/offer', builder: (_, _) => const AddGuardOfferScreen()),
      GoRoute(path: '/training', builder: (_, _) => const TrainingScreen()),
      GoRoute(path: '/training/apply', builder: (_, _) => const ApplyTrainerScreen()),
      GoRoute(path: '/admin/trainer-applications', builder: (_, _) => const AdminTrainerApplicationsScreen()),
      GoRoute(path: '/trainers/:id', builder: (_, s) => TrainerDetailScreen(trainerId: s.pathParameters['id']!)),
      GoRoute(path: '/favorites', builder: (_, _) => const FavoritesScreen()),
      GoRoute(
        path: '/adoption-requests',
        builder: (_, s) => AdoptionRequestsScreen(initialTab: s.uri.queryParameters['tab']),
      ),
      GoRoute(path: '/my-pets', builder: (_, _) => const MyPetsScreen()),
      GoRoute(path: '/add-pet', builder: (_, _) => const AddPetScreen()),
      GoRoute(
        path: '/edit-pet/:id',
        builder: (_, s) => EditPetScreen(
          petId: s.pathParameters['id']!,
          fromOnboarding: s.uri.queryParameters['onboarding'] == '1',
        ),
      ),
      GoRoute(
        path: '/pet-health/:id',
        builder: (_, s) => PetHealthScreen(
          petId: s.pathParameters['id']!,
          petName: s.uri.queryParameters['name'],
        ),
      ),
      GoRoute(path: '/product/:id', builder: (_, s) => ProductDetailScreen(productId: s.pathParameters['id']!)),
      GoRoute(path: '/cart', builder: (_, _) => const CartScreen()),
      GoRoute(path: '/checkout', builder: (_, _) => const CheckoutScreen()),
      GoRoute(
        path: '/order-success',
        builder: (_, s) => OrderSuccessScreen(order: s.extra is Order ? s.extra as Order : null),
      ),
      GoRoute(path: '/orders', builder: (_, _) => const OrdersScreen()),
      GoRoute(
        path: '/vets',
        builder: (_, s) => VetsScreen(petId: s.uri.queryParameters['petId']),
      ),
      GoRoute(path: '/vet/appointments', builder: (_, _) => const VetClinicAppointmentsScreen()),
      GoRoute(
        path: '/vet/:id',
        builder: (_, s) => VetDetailScreen(
          vetId: s.pathParameters['id']!,
          petId: s.uri.queryParameters['petId'],
        ),
      ),
      GoRoute(
        path: '/book-appointment/:vetId',
        builder: (_, s) => BookAppointmentScreen(
          vetId: s.pathParameters['vetId']!,
          vet: s.extra is Vet ? s.extra as Vet : null,
          initialPetId: s.uri.queryParameters['petId'],
        ),
      ),
      GoRoute(path: '/appointments', builder: (_, _) => const AppointmentsScreen()),
      GoRoute(
        path: '/lost-found',
        builder: (_, s) => LostFoundScreen(initialType: s.uri.queryParameters['type']),
      ),
      GoRoute(path: '/lost-found/report', builder: (_, _) => const ReportLostFoundScreen()),
      GoRoute(
        path: '/lost-found/map',
        builder: (_, s) => LostFoundMapScreen(
          initialType: s.uri.queryParameters['type'],
          focusPostId: s.uri.queryParameters['focus'],
        ),
      ),
      GoRoute(
        path: '/lost-found/:id',
        builder: (_, s) => LostFoundDetailScreen(postId: s.pathParameters['id']!),
      ),
      GoRoute(path: '/community', builder: (_, _) => const CommunityScreen()),
      GoRoute(path: '/community/:id', builder: (_, s) => PostDetailScreen(postId: s.pathParameters['id']!)),
      GoRoute(path: '/create-post', builder: (_, _) => const CreatePostScreen()),
      GoRoute(
        path: '/users/:id',
        builder: (_, s) => UserProfileScreen(userId: s.pathParameters['id']!),
      ),
      GoRoute(path: '/friends', builder: (_, _) => const FriendsScreen()),
      GoRoute(path: '/friends/search', builder: (_, _) => const FriendSearchScreen()),
      GoRoute(path: '/friends/activity', builder: (_, _) => const FriendsActivityScreen()),
      GoRoute(
        path: '/friends/invite',
        builder: (_, s) => InviteFriendsScreen(
          initialCode: s.uri.queryParameters['code'],
          autoScan: s.uri.queryParameters['scan'] == '1',
        ),
      ),
      GoRoute(
        path: '/invite/:code',
        builder: (_, s) => InviteFriendsScreen(initialCode: s.pathParameters['code']),
      ),
      GoRoute(path: '/chat/:id', builder: (_, s) => ChatScreen(conversationId: s.pathParameters['id']!)),
      GoRoute(path: '/notifications', builder: (_, _) => const NotificationsScreen()),
      GoRoute(path: '/edit-profile', builder: (_, _) => const EditProfileScreen()),
    ],
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(),
      body: Center(child: Text(state.uri.toString())),
    ),
  );
}
