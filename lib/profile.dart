import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geocoding/geocoding.dart';
import 'package:location/location.dart' as loc;
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'supabase_service.dart';
import 'models.dart';
import 'requests_pages.dart';
import 'my_list.dart';
import 'my_collection.dart';
import 'homepage.dart';
import 'merit_system.dart';
import 'merit_history.dart';
import 'nid_verification.dart';
import 'admin_panel.dart';
import 'upload.dart' show LocationPickerMap;

// ─────────────────────────────────────────────────────────────
// LoginScreen
// ─────────────────────────────────────────────────────────────
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const Color primaryColor = Color(0xFF381932);
  static const Color backgroundColor = Color(0xFFF0EDE9);

  bool _isLogin = true;
  bool _loading = false;

  final _formKey = GlobalKey<FormState>();

  // Shared
  final _emailCtrl = TextEditingController();
  final _passCtrl  = TextEditingController();

  // Sign-up only
  final _nameCtrl    = TextEditingController();
  final _confirmCtrl = TextEditingController();

  // Visibility toggles
  bool _obscurePass    = true;
  bool _obscureConfirm = true;

  // Per-field server-side error messages (shown via validator)
  String? _emailError;
  String? _passError;
  String? _nameError;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _nameCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  bool _isValidEmail(String v) =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim());

  String? _validatePasswordStrength(String? v) {
    if (v == null || v.isEmpty) return 'Password required';
    if (v.length < 8)                                   return 'Minimum 8 characters';
    if (!v.contains(RegExp(r'[A-Z]')))                  return 'Add at least one uppercase letter (A–Z)';
    if (!v.contains(RegExp(r'[a-z]')))                  return 'Add at least one lowercase letter (a–z)';
    if (!v.contains(RegExp(r'[0-9]')))                  return 'Add at least one digit (0–9)';
    if (!v.contains(RegExp(r'[!@#\$%^&*(),.?":{}|<>_\-=+\[\]\\;`~\/]'))) {
      return 'Add at least one special character (!@#\$%...)';
    }
    return null;
  }

  void _clearServerErrors() {
    _emailError = null;
    _passError  = null;
    _nameError  = null;
  }

  // ── Submit ────────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    _clearServerErrors();
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);

    try {
      if (_isLogin) {
        await _doLogin();
      } else {
        await _doSignUp();
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _doLogin() async {
    final email = _emailCtrl.text.trim();
    final pass  = _passCtrl.text;

    try {
      final res = await SupabaseService.signIn(email, pass);
      if (res.user != null && mounted) {
        Navigator.pushReplacement(
            context, MaterialPageRoute(builder: (_) => const HomePage()));
      }
    } on AuthException catch (e) {
      if (!mounted) return;
      final msg = e.message.toLowerCase();

      if (msg.contains('invalid login credentials') ||
          msg.contains('invalid_credentials') ||
          msg.contains('wrong password') ||
          msg.contains('invalid password')) {
        // Distinguish "email not found" vs "wrong password"
        final exists = await _emailExists(email);
        if (!exists) {
          _emailError = 'No account found with this email address';
        } else {
          _passError = 'Incorrect password. Try again or use Forgot Password';
        }
      } else if (msg.contains('email not confirmed')) {
        _showSnackError('Please confirm your email before logging in. Check your inbox.');
        return;
      } else if (msg.contains('user not found') ||
          msg.contains('no user') ||
          msg.contains('not_found')) {
        _emailError = 'No account found with this email address';
      } else if (msg.contains('too many requests') ||
          msg.contains('rate limit')) {
        _showSnackError('Too many attempts. Please wait a moment and try again.');
        return;
      } else {
        _showSnackError(e.message);
        return;
      }

      setState(() {});
      _formKey.currentState!.validate();
    } catch (e) {
      if (mounted) _showSnackError('Unexpected error: $e');
    }
  }

  Future<void> _doSignUp() async {
    final email = _emailCtrl.text.trim();
    final pass  = _passCtrl.text;
    final name  = _nameCtrl.text.trim();

    // Check username uniqueness before calling auth
    final nameTaken = await _isNameTaken(name);
    if (nameTaken) {
      setState(() => _nameError = 'Username already taken, try another');
      _formKey.currentState!.validate();
      return;
    }

    try {
      final res = await SupabaseService.signUp(email, pass, fullName: name);
      if (res.user != null && mounted) {
        try {
          await SupabaseService.upsertProfile({
            'id': res.user!.id,
            'full_name': name,
            'email': email,
            'merit_points': 70,
            'total_merit_earned': 0,
            'total_merit_lost': 0,
            'daily_merit_gain': 0,
            'wallet_balance': 0.0,
            'reward_points': 0,
            'nid_verified': false,
            'is_admin': false,
            'is_banned': false,
          });
        } catch (_) {}
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Account created! Check your email to confirm, then log in.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 5),
          ));
          setState(() {
            _isLogin = true;
            _clearServerErrors();
          });
        }
      }
    } on AuthException catch (e) {
      if (!mounted) return;
      final msg = e.message.toLowerCase();
      if (msg.contains('already registered') ||
          msg.contains('user_already_exists') ||
          msg.contains('already exists')) {
        _emailError = 'An account with this email already exists. Try logging in.';
        setState(() {});
        _formKey.currentState!.validate();
      } else if (msg.contains('invalid email') ||
          msg.contains('unable to validate')) {
        _emailError = 'This email address is not valid';
        setState(() {});
        _formKey.currentState!.validate();
      } else {
        _showSnackError(e.message);
      }
    } catch (e) {
      if (mounted) _showSnackError('Unexpected error: $e');
    }
  }

  /// Returns true if the email already has a profile row (account exists).
  Future<bool> _emailExists(String email) async {
    try {
      final data = await SupabaseService.client
          .from('profiles')
          .select('id')
          .eq('email', email.toLowerCase())
          .maybeSingle();
      return data != null;
    } catch (_) {
      return false;
    }
  }

  /// Returns true if any profile already uses this full_name (case-insensitive).
  Future<bool> _isNameTaken(String name) async {
    if (name.isEmpty) return false;
    try {
      final data = await SupabaseService.client
          .from('profiles')
          .select('id')
          .ilike('full_name', name)
          .maybeSingle();
      return data != null;
    } catch (_) {
      return false;
    }
  }

  void _showSnackError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 40),
                // ── App Logo (large) ──────────────────────────────────────────
                Center(
                  child: Image.asset(
                    'assets/loading_screen-removebg-preview.png',
                    width: 350,
                    height: 350,
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(height: 0),
                // ── Welcome message ──────────────────────────────────────────
                Center(
                  child: Text(
                    _isLogin ? 'Welcome Back!' : 'Create an Account',
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    _isLogin
                        ? 'Sign in to continue'
                        : 'Join the Rental Market today',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 15,
                    ),
                  ),
                ),
                const SizedBox(height: 40),

                // ── Name (sign-up only) ──────────────────────────────────
                if (!_isLogin) ...[
                  _label('Full Name'),
                  TextFormField(
                    controller: _nameCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: _inputDec('Enter your full name', Icons.person_outline),
                    onChanged: (_) {
                      if (_nameError != null) setState(() => _nameError = null);
                    },
                    validator: (v) {
                      if (_nameError != null) return _nameError;
                      if (v == null || v.trim().isEmpty) return 'Name is required';
                      if (v.trim().length < 2) return 'Name is too short';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                ],

                // ── Email ────────────────────────────────────────────────
                _label('Email Address'),
                TextFormField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: _inputDec('Enter your email', Icons.email_outlined),
                  onChanged: (_) {
                    if (_emailError != null) setState(() => _emailError = null);
                  },
                  validator: (v) {
                    if (_emailError != null) return _emailError;
                    if (v == null || v.trim().isEmpty) return 'Email is required';
                    if (!_isValidEmail(v)) return 'Enter a valid email address (e.g. name@example.com)';
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // ── Password ─────────────────────────────────────────────
                _label('Password'),
                TextFormField(
                  controller: _passCtrl,
                  obscureText: _obscurePass,
                  decoration: _inputDec('Enter password', Icons.lock_outline).copyWith(
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePass ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => _obscurePass = !_obscurePass),
                    ),
                  ),
                  onChanged: (_) {
                    if (_passError != null) setState(() => _passError = null);
                  },
                  validator: (v) {
                    if (_passError != null) return _passError;
                    if (_isLogin) {
                      return (v == null || v.isEmpty) ? 'Password required' : null;
                    }
                    return _validatePasswordStrength(v);
                  },
                ),

                // ── Confirm Password (sign-up only) ──────────────────────
                if (!_isLogin) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Password must be at least 8 characters and include uppercase, lowercase, a number, and a special character.',
                      style: TextStyle(fontSize: 11, color: Colors.blueGrey),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _label('Confirm Password'),
                  TextFormField(
                    controller: _confirmCtrl,
                    obscureText: _obscureConfirm,
                    decoration: _inputDec('Re-enter your password', Icons.lock_outline).copyWith(
                      suffixIcon: IconButton(
                        icon: Icon(_obscureConfirm ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                      ),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Please confirm your password';
                      if (v != _passCtrl.text) return 'Passwords do not match';
                      return null;
                    },
                  ),
                ],

                // ── Forgot Password (login only) ─────────────────────────
                if (_isLogin) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: GestureDetector(
                      onTap: _showForgotPassword,
                      child: Text(
                        'Forgot Password?',
                        style: TextStyle(
                          color: primaryColor,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 32),

                // ── Submit button ────────────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: _loading
                        ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(Colors.white)),
                    )
                        : Text(
                      _isLogin ? 'Log In' : 'Create Account',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // ── Switch mode ──────────────────────────────────────────
                Center(
                  child: GestureDetector(
                    onTap: () => setState(() {
                      _isLogin = !_isLogin;
                      _clearServerErrors();
                      _formKey.currentState?.reset();
                    }),
                    child: RichText(
                      text: TextSpan(
                        style: const TextStyle(fontSize: 15, color: Colors.black87),
                        children: [
                          TextSpan(
                              text: _isLogin
                                  ? "Don't have an account? "
                                  : 'Already have an account? '),
                          TextSpan(
                              text: _isLogin ? 'Register' : 'Log In',
                              style: TextStyle(
                                  color: primaryColor,
                                  fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showForgotPassword() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ForgotPasswordSheet(primaryColor: primaryColor),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(text,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
  );

  InputDecoration _inputDec(String hint, IconData icon) => InputDecoration(
    hintText: hint,
    prefixIcon: Icon(icon, color: Colors.grey),
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
    enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade200)),
    focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF381932), width: 1.5)),
    errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.red)),
    focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.red)),
  );
}


// ─────────────────────────────────────────────────────────────
// _ForgotPasswordSheet
// ─────────────────────────────────────────────────────────────
class _ForgotPasswordSheet extends StatefulWidget {
  final Color primaryColor;
  const _ForgotPasswordSheet({required this.primaryColor});

  @override
  State<_ForgotPasswordSheet> createState() => _ForgotPasswordSheetState();
}

class _ForgotPasswordSheetState extends State<_ForgotPasswordSheet> {
  final _emailCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _loading = false;
  bool _sent = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await SupabaseService.resetPassword(_emailCtrl.text.trim());
      if (mounted) setState(() { _loading = false; _sent = true; });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final primary = widget.primaryColor;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(24, 12, 24, 24 + bottom),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Icon
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(
                color: primary.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.lock_reset, size: 32, color: primary),
            ),
            const SizedBox(height: 16),

            Text(
              _sent ? 'Email Sent!' : 'Reset Password',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _sent
                  ? "Check your inbox for a password reset link. It may take a minute to arrive."
                  : "Enter your account email and we'll send you a link to reset your password.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
            ),
            const SizedBox(height: 24),

            if (_sent) ...[
              // Success state
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Row(children: [
                  Icon(Icons.mark_email_read_outlined,
                      color: Colors.green.shade600, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _emailCtrl.text.trim(),
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Reset link sent',
                          style: TextStyle(
                              color: Colors.green.shade700, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Back to Login',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 12),
              // Resend option
              GestureDetector(
                onTap: () => setState(() => _sent = false),
                child: Text(
                  "Didn't receive it? Try again",
                  style: TextStyle(
                    color: primary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ] else ...[
              // Email input state
              TextFormField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  hintText: 'Enter your email address',
                  prefixIcon: const Icon(Icons.email_outlined,
                      color: Colors.grey),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: primary, width: 1.5),
                  ),
                  errorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.red),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                ),
                validator: (v) =>
                (v == null || !v.contains('@'))
                    ? 'Enter a valid email address'
                    : null,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _loading ? null : _send,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _loading
                      ? const SizedBox(
                    height: 20, width: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                      : const Text('Send Reset Link',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Text(
                  'Cancel',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// ProfileScreen
// ─────────────────────────────────────────────────────────────
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  static const Color primaryColor = Color(0xFF381932);
  static const Color backgroundColor = Color(0xFFF0EDE9);

  AppUser? _user;
  UserMerit? _merit;
  bool _loading = true;
  bool _uploadingAvatar = false;
  bool _isVerified = false;
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final uid = SupabaseService.currentUserId;
    final email = SupabaseService.currentUser?.email ?? '';
    if (uid == null) return;
    try {
      final profile = await SupabaseService.fetchProfile(uid);
      final merit = await MeritService.getUserMerit(uid);
      final isAdmin = await SupabaseService.isAdmin();
      if (mounted) {
        setState(() {
          if (profile != null) {
            _user = AppUser.fromMap(uid, email, profile);
          } else {
            // Fallback: use auth metadata for the name
            final authMeta =
                SupabaseService.currentUser?.userMetadata;
            final nameFromMeta =
                authMeta?['full_name'] as String? ?? email.split('@')[0];
            _user = AppUser(id: uid, email: email, fullName: nameFromMeta);
          }
          _merit = merit;
          _isVerified = profile?['nid_verified'] == true;
          _isAdmin = isAdmin;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Upload avatar to Supabase Storage bucket 'avatars' and update profile
  Future<void> _pickAndUploadAvatar() async {
    final picker = ImagePicker();
    final uid = SupabaseService.currentUserId;
    if (uid == null) return;

    final XFile? picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 80,
    );
    if (picked == null) return;

    setState(() => _uploadingAvatar = true);
    try {
      // readAsBytes() works on Web AND Mobile — no dart:io File needed
      final Uint8List bytes = await picked.readAsBytes();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = '$uid/$timestamp.jpg';

      await SupabaseService.client.storage.from('avatars').uploadBinary(
        fileName,
        bytes,
        fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
      );

      final publicUrl = SupabaseService.client.storage
          .from('avatars')
          .getPublicUrl(fileName);

      await SupabaseService.upsertProfile({'id': uid, 'avatar_url': publicUrl});
      await _loadProfile();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Profile picture updated!'),
          backgroundColor: Color(0xFF381932),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Upload failed: $e'),
            backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  Future<void> _logout() async {
    await SupabaseService.signOut();
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
            (_) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final merit = _merit ?? UserMerit.defaultMerit();
    final tier = merit.tier;
    final tierColor = Color(tier.color as int);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        title: const Text('Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const SettingsPage())),
          ),
          IconButton(
              icon: const Icon(Icons.logout),
              onPressed: _logout,
              tooltip: 'Logout'),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
        onRefresh: _loadProfile,
        color: primaryColor,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const SizedBox(height: 12),

              // ── Avatar ──
              Stack(
                alignment: Alignment.bottomRight,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: _isAdmin ? Colors.amber : tierColor,
                          width: 3),
                      boxShadow: [
                        BoxShadow(
                            color: (_isAdmin ? Colors.amber : tierColor)
                                .withOpacity(0.3),
                            blurRadius: 16,
                            spreadRadius: 2)
                      ],
                    ),
                    child: CircleAvatar(
                      radius: 56,
                      backgroundImage: (_user?.avatarUrl != null &&
                          _user!.avatarUrl!.isNotEmpty)
                          ? NetworkImage(_user!.avatarUrl!)
                          : null,
                      backgroundColor:
                      primaryColor.withOpacity(0.2),
                      child: (_user?.avatarUrl == null ||
                          _user!.avatarUrl!.isEmpty)
                          ? const Icon(Icons.person,
                          size: 56, color: Colors.white)
                          : null,
                    ),
                  ),
                  GestureDetector(
                    onTap:
                    _uploadingAvatar ? null : _pickAndUploadAvatar,
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: primaryColor,
                        shape: BoxShape.circle,
                        border:
                        Border.all(color: Colors.white, width: 2),
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 4)
                        ],
                      ),
                      child: _uploadingAvatar
                          ? const Padding(
                        padding: EdgeInsets.all(8),
                        child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation(
                                Colors.white)),
                      )
                          : const Icon(Icons.camera_alt,
                          color: Colors.white, size: 18),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // ── User Name (from profile / auth metadata) ──
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    // Show full_name from profile; fallback to auth metadata name
                    _user?.fullName.isNotEmpty == true
                        ? _user!.fullName
                        : (SupabaseService.currentUser
                        ?.userMetadata?['full_name'] as String? ??
                        'User'),
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  if (_isAdmin) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade100,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.admin_panel_settings,
                              size: 14, color: Colors.amber),
                          SizedBox(width: 4),
                          Text('Admin',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.amber)),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              Text(_user?.email ?? '',
                  style: TextStyle(
                      color: Colors.grey.shade600, fontSize: 13)),
              if (_user?.hasAddress == true) ...[
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.location_on, size: 13, color: Colors.grey.shade500),
                    const SizedBox(width: 3),
                    Flexible(
                      child: Text(
                        _user!.address!,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 6),

              // Verification badge
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: _isVerified
                      ? Colors.green.shade50
                      : Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: _isVerified
                          ? Colors.green.shade200
                          : Colors.orange.shade200),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _isVerified
                          ? Icons.verified
                          : Icons.warning_amber,
                      color: _isVerified
                          ? Colors.green
                          : Colors.orange,
                      size: 14,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _isVerified
                          ? 'NID Verified'
                          : 'NID Not Verified',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: _isVerified
                            ? Colors.green
                            : Colors.orange,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // ── Merit Card (only for non-admins) ──
              if (!_isAdmin)
                GestureDetector(
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(
                          builder: (_) => const MeritHistoryPage())),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: tierColor.withOpacity(0.25)),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withOpacity(0.06),
                            blurRadius: 14,
                            offset: const Offset(0, 4))
                      ],
                    ),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                              mainAxisAlignment:
                              MainAxisAlignment.spaceBetween,
                              children: [
                                Row(children: [
                                  Icon(Icons.military_tech,
                                      color: tierColor, size: 22),
                                  const SizedBox(width: 8),
                                  const Text('Merit Score',
                                      style: TextStyle(
                                          fontSize: 15,
                                          fontWeight:
                                          FontWeight.bold)),
                                ]),
                                Row(children: [
                                  Text('${merit.points}/100',
                                      style: TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.bold,
                                          color: tierColor)),
                                  const SizedBox(width: 6),
                                  const Icon(Icons.chevron_right,
                                      color: Colors.grey, size: 20),
                                ]),
                              ]),
                          const SizedBox(height: 12),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: LinearProgressIndicator(
                              value: merit.points / 100,
                              minHeight: 12,
                              backgroundColor: Colors.grey.shade200,
                              valueColor:
                              AlwaysStoppedAnimation<Color>(tierColor),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                              mainAxisAlignment:
                              MainAxisAlignment.spaceBetween,
                              children: [
                                _scaleTick('0', const Color(0xFF424242)),
                                _scaleTick('20', const Color(0xFFB71C1C)),
                                _scaleTick('40', const Color(0xFFFF6F00)),
                                _scaleTick('70', const Color(0xFF2E7D32)),
                                _scaleTick('90', const Color(0xFFFFD700)),
                              ]),
                          const SizedBox(height: 10),
                          Text(tier.description,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600)),
                          if (!merit.canRent) ...[
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                    color: Colors.red.shade200),
                              ),
                              child: Row(children: [
                                Icon(Icons.warning_amber,
                                    color: Colors.red.shade700,
                                    size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                    child: Text(
                                      'Your merit is below 40. You cannot rent items until you reach 40+ points.',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.red.shade700),
                                    )),
                              ]),
                            ),
                          ],
                          const SizedBox(height: 8),
                          Row(children: [
                            Icon(Icons.info_outline,
                                size: 13,
                                color: Colors.grey.shade500),
                            const SizedBox(width: 4),
                            Text(
                                'Daily gain remaining: +${merit.remainingDailyGain} pts',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade500)),
                            const Spacer(),
                            Text('Tap for history →',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: tierColor,
                                    fontWeight: FontWeight.w500)),
                          ]),
                        ]),
                  ),
                ),

              if (!_isAdmin) const SizedBox(height: 20),

              // ── My Listings & Rentals ──
              Row(children: [
                Expanded(
                    child: _ProfileCard(
                      title: 'My Listings',
                      subtitle: 'Items you offer',
                      icon: Icons.list_alt,
                      color: Colors.blue,
                      onTap: () => Navigator.push(context,
                          MaterialPageRoute(
                              builder: (_) => const MyListPage())),
                    )),
                const SizedBox(width: 14),
                Expanded(
                    child: _ProfileCard(
                      title: 'My Rentals',
                      subtitle: 'Items you rented',
                      icon: Icons.favorite,
                      color: Colors.pink,
                      onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                              const MyCollectionPage())),
                    )),
              ]),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                    child: _ProfileCard(
                      title: 'Rent Requests',
                      subtitle: 'Rentals management',
                      icon: Icons.handshake_outlined,
                      color: Colors.deepPurple,
                      onTap: () => Navigator.push(context,
                          MaterialPageRoute(
                              builder: (_) => const RequestsTabsPage(isRent: true))),
                    )),
                const SizedBox(width: 14),
                Expanded(
                    child: _ProfileCard(
                      title: 'Buy Requests',
                      subtitle: 'Purchase management',
                      icon: Icons.shopping_bag_outlined,
                      color: Colors.orange,
                      onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const RequestsTabsPage(isRent: false))),
                    )),
              ]),
              const SizedBox(height: 24),

              // ── Menu items ──
              if (!_isAdmin)
                _MenuItem(
                    icon: Icons.military_tech,
                    title: 'Merit History',
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(
                            builder: (_) => const MeritHistoryPage()))),
              if (!_isAdmin) const Divider(height: 1),

              _MenuItem(
                icon: Icons.credit_card_outlined,
                title: _isVerified ? 'NID Verified ✓' : 'Verify NID',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const NIDVerificationPage()),
                ).then((_) => _loadProfile()),
                color: _isVerified ? Colors.green : null,
              ),
              const Divider(height: 1),

              if (_isAdmin) ...[
                _MenuItem(
                  icon: Icons.admin_panel_settings,
                  title: 'Admin Panel',
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(
                          builder: (_) => const AdminPanelPage())),
                  color: Colors.amber,
                ),
                const Divider(height: 1),
              ],

              _MenuItem(
                  icon: Icons.settings_outlined,
                  title: 'Settings',
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(
                          builder: (_) => const SettingsPage()))),
              const Divider(height: 1),
              _MenuItem(
                  icon: Icons.account_circle_outlined,
                  title: 'Edit Profile',
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) =>
                          const EditProfilePage()))
                      .then((_) => _loadProfile())),
              const Divider(height: 1),
              _MenuItem(
                  icon: Icons.help_outline,
                  title: 'Help & Support',
                  onTap: () {}),
              const Divider(height: 1),
              _MenuItem(
                  icon: Icons.privacy_tip_outlined,
                  title: 'Privacy Policy',
                  onTap: () {}),
              const Divider(height: 1),
              _MenuItem(
                  icon: Icons.logout,
                  title: 'Log Out',
                  onTap: _logout,
                  color: Colors.red),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _scaleTick(String label, Color color) {
    return Column(children: [
      Container(width: 2, height: 6, color: color),
      const SizedBox(height: 2),
      Text(label,
          style: TextStyle(
              fontSize: 9, color: color, fontWeight: FontWeight.bold)),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────
// EditProfilePage — requires password to save changes
// ─────────────────────────────────────────────────────────────
class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  static const Color primaryColor = Color(0xFF381932);
  static const Color backgroundColor = Color(0xFFF0EDE9);

  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  bool _loading = false;
  bool _saving = false;

  LatLng? _selectedLocation;
  bool _isMapLoading = false;

  // Google Maps API key — must match AndroidManifest.xml & Info.plist
  // (same key used in upload.dart)
  static const String _googleApiKey = 'AIzaSyC1Lr5p_w2AnxPNgdsvqVCwnMPwxOlUGA0';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _bioCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final uid = SupabaseService.currentUserId;
    if (uid == null) return;
    final profile = await SupabaseService.fetchProfile(uid);
    if (profile != null && mounted) {
      _nameCtrl.text = profile['full_name'] ?? '';
      _phoneCtrl.text = profile['phone'] ?? '';
      _bioCtrl.text = profile['bio'] ?? '';
      _addressCtrl.text = profile['address'] ?? '';
      final lat = (profile['latitude'] as num?)?.toDouble();
      final lng = (profile['longitude'] as num?)?.toDouble();
      if (lat != null && lng != null) {
        _selectedLocation = LatLng(lat, lng);
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  // ── Map / location helpers ─────────────────────────────────────────────

  Future<void> _openMap() async {
    final status = await Permission.location.request();
    if (status.isDenied) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Location permission is required to use the map feature'),
          backgroundColor: Colors.orange,
        ));
      }
      return;
    }
    if (status.isPermanentlyDenied) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Please enable location permission in app settings'),
          backgroundColor: Colors.red,
        ));
      }
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LocationPickerMap(
          initialLocation: _selectedLocation,
          onLocationSelected: (LatLng location, String address) {
            setState(() {
              _selectedLocation = location;
              _addressCtrl.text = address;
            });
          },
        ),
      ),
    );
  }

  Future<void> _getCurrentLocation() async {
    setState(() => _isMapLoading = true);
    try {
      PermissionStatus permissionStatus = await Permission.location.request();
      if (!permissionStatus.isGranted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Location permission denied')));
        }
        setState(() => _isMapLoading = false);
        return;
      }

      loc.Location location = loc.Location();
      bool serviceEnabled = await location.serviceEnabled();
      if (!serviceEnabled) {
        serviceEnabled = await location.requestService();
        if (!serviceEnabled) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Location services are disabled')));
          }
          setState(() => _isMapLoading = false);
          return;
        }
      }

      loc.LocationData currentLocation = await location.getLocation();
      LatLng currentLatLng = LatLng(
          currentLocation.latitude ?? 0, currentLocation.longitude ?? 0);
      String address = await _getAddressFromLatLng(currentLatLng);

      setState(() {
        _selectedLocation = currentLatLng;
        _addressCtrl.text = address;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Location detected: $address'),
                backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error getting location: $e'),
                backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isMapLoading = false);
    }
  }

  Future<String> _getAddressFromLatLng(LatLng position) async {
    final latlng = '${position.latitude},${position.longitude}';
    try {
      final uri = Uri.https('maps.googleapis.com', '/maps/api/geocode/json', {
        'latlng': latlng,
        'key': _googleApiKey,
        'language': 'en',
      });
      final response = await http.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data['status'] == 'OK') {
          final results = data['results'] as List<dynamic>;
          if (results.isNotEmpty) {
            return results.first['formatted_address'] as String? ?? 'Selected location';
          }
        }
      }
    } catch (_) {}
    try {
      final placemarks = await placemarkFromCoordinates(
          position.latitude, position.longitude);
      if (placemarks.isNotEmpty) return _formatDetailedAddress(placemarks[0]);
    } catch (_) {}
    return 'Selected location';
  }

  String _formatDetailedAddress(Placemark place) {
    List<String> parts = [];
    String street = '';
    if (place.subThoroughfare != null && place.subThoroughfare!.isNotEmpty) {
      street = '${place.subThoroughfare} ${place.thoroughfare ?? ''}'.trim();
    } else if (place.thoroughfare != null && place.thoroughfare!.isNotEmpty) {
      street = place.thoroughfare!;
    } else if (place.street != null && place.street!.isNotEmpty) {
      street = place.street!;
    }
    if (street.isNotEmpty) parts.add(street);
    if (place.subLocality?.isNotEmpty == true) parts.add(place.subLocality!);
    if (place.locality?.isNotEmpty == true) parts.add(place.locality!);
    if (place.postalCode?.isNotEmpty == true) parts.add(place.postalCode!);
    if (place.administrativeArea?.isNotEmpty == true) {
      parts.add(place.administrativeArea!);
    }
    if (place.country?.isNotEmpty == true) parts.add(place.country!);
    return parts.isEmpty ? 'Selected location' : parts.join(', ');
  }

  // Geocode a manually typed address into coordinates
  Future<void> _geocodeManualAddress() async {
    final address = _addressCtrl.text.trim();
    if (address.isEmpty) return;
    setState(() => _isMapLoading = true);
    try {
      final uri = Uri.https('maps.googleapis.com', '/maps/api/geocode/json', {
        'address': address,
        'key': _googleApiKey,
        'language': 'en',
      });
      final response = await http.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data['status'] == 'OK') {
          final results = data['results'] as List<dynamic>;
          if (results.isNotEmpty) {
            final geoLoc = results.first['geometry']['location'];
            final lat = (geoLoc['lat'] as num).toDouble();
            final lng = (geoLoc['lng'] as num).toDouble();
            setState(() => _selectedLocation = LatLng(lat, lng));
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Location coordinates updated!'),
                  backgroundColor: Colors.green));
            }
            return;
          }
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not geocode this address. Try a more specific location.'),
            backgroundColor: Colors.orange));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Geocoding failed: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isMapLoading = false);
    }
  }

  /// Show a dialog asking for the current password and verify it with Supabase
  Future<bool> _requirePasswordConfirmation() async {
    final passwordCtrl = TextEditingController();
    bool obscure = true;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        return AlertDialog(
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Confirm Password',
              style: TextStyle(fontWeight: FontWeight.bold)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text(
                'Enter your current password to save profile changes.',
                style: TextStyle(fontSize: 13, color: Colors.grey)),
            const SizedBox(height: 16),
            TextField(
              controller: passwordCtrl,
              obscureText: obscure,
              decoration: InputDecoration(
                hintText: 'Current password',
                prefixIcon:
                const Icon(Icons.lock_outline, color: Colors.grey),
                suffixIcon: IconButton(
                  icon: Icon(
                      obscure ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setS(() => obscure = !obscure),
                ),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
              ),
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Confirm'),
            ),
          ],
        );
      }),
    );

    if (confirmed != true) return false;
    if (passwordCtrl.text.isEmpty) return false;

    // Verify password by attempting sign-in
    final email = SupabaseService.currentUser?.email;
    if (email == null) return false;
    try {
      await SupabaseService.signIn(email, passwordCtrl.text);
      return true;
    } on AuthException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Incorrect password. Changes not saved.'),
            backgroundColor: Colors.red));
      }
      return false;
    }
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Name cannot be empty')));
      return;
    }
    final uid = SupabaseService.currentUserId;
    if (uid == null) return;

    // Require password confirmation before saving
    final authenticated = await _requirePasswordConfirmation();
    if (!authenticated) return;

    setState(() => _saving = true);
    try {
      await SupabaseService.upsertProfile({
        'id': uid,
        'full_name': _nameCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        'bio': _bioCtrl.text.trim(),
        'address': _addressCtrl.text.trim(),
        'latitude': _selectedLocation?.latitude,
        'longitude': _selectedLocation?.longitude,
      });

      // Merit bonus for completing profile
      await MeritService.processCompleteProfile(uid);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Profile updated successfully!'),
            backgroundColor: Color(0xFF381932)));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('Error saving: $e'),
                backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        title: const Text('Edit Profile'),
        centerTitle: true,
        leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context)),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: const Text('Save',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16)),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Info banner
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade100),
              ),
              child: Row(children: [
                Icon(Icons.info_outline,
                    color: Colors.blue.shade700, size: 18),
                const SizedBox(width: 8),
                const Expanded(
                    child: Text(
                      'You will be asked for your current password before saving changes.',
                      style: TextStyle(fontSize: 12),
                    )),
              ]),
            ),
            _label('Full Name'),
            _field(_nameCtrl, 'Your full name', Icons.person_outline),
            const SizedBox(height: 16),
            _label('Phone Number'),
            _field(_phoneCtrl, '+880 1xxx xxxxxx', Icons.phone_outlined),
            const SizedBox(height: 16),
            _label('Bio'),
            TextFormField(
              controller: _bioCtrl,
              maxLines: 3,
              decoration: _inputDec(
                  'A short bio about yourself', Icons.info_outline),
            ),
            const SizedBox(height: 16),
            _label('Address / Location'),
            TextFormField(
              controller: _addressCtrl,
              maxLines: 2,
              decoration: InputDecoration(
                hintText: 'Your address or area, e.g. Zindabazar, Sylhet',
                prefixIcon: const Icon(Icons.location_on, color: Colors.grey),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(Icons.my_location, color: primaryColor),
                      onPressed: _isMapLoading ? null : _getCurrentLocation,
                      tooltip: 'Use current location',
                    ),
                    IconButton(
                      icon: Icon(Icons.map_outlined, color: primaryColor),
                      onPressed: _isMapLoading ? null : _openMap,
                      tooltip: 'Pick on map',
                    ),
                  ],
                ),
                filled: true,
                fillColor: Colors.white,
                contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade200)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: primaryColor, width: 1.5)),
              ),
              onFieldSubmitted: (_) => _geocodeManualAddress(),
            ),
            if (_isMapLoading)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: LinearProgressIndicator(minHeight: 2),
              ),
            if (_selectedLocation != null) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  height: 140,
                  child: Stack(
                    children: [
                      GoogleMap(
                        initialCameraPosition: CameraPosition(
                            target: _selectedLocation!, zoom: 15),
                        markers: {
                          Marker(
                              markerId: const MarkerId('profile_location'),
                              position: _selectedLocation!),
                        },
                        liteModeEnabled: true,
                        zoomControlsEnabled: false,
                        myLocationButtonEnabled: false,
                        scrollGesturesEnabled: false,
                      ),
                      Positioned(
                        right: 8,
                        bottom: 8,
                        child: Material(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: _isMapLoading ? null : _openMap,
                            child: const Padding(
                              padding: EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.edit_location, size: 14),
                                  SizedBox(width: 4),
                                  Text('Edit', style: TextStyle(fontSize: 12)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: _saving
                    ? const SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor:
                      AlwaysStoppedAnimation(Colors.white)),
                )
                    : const Text('Save Changes',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(text,
        style:
        const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
  );

  Widget _field(TextEditingController ctrl, String hint, IconData icon) {
    return TextFormField(
        controller: ctrl, decoration: _inputDec(hint, icon));
  }

  InputDecoration _inputDec(String hint, IconData icon) => InputDecoration(
    hintText: hint,
    prefixIcon: Icon(icon, color: Colors.grey),
    filled: true,
    fillColor: Colors.white,
    contentPadding:
    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none),
    enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade200)),
    focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide:
        const BorderSide(color: primaryColor, width: 1.5)),
  );
}

// ─────────────────────────────────────────────────────────────
// SettingsPage
// ─────────────────────────────────────────────────────────────
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  static const Color primaryColor = Color(0xFF381932);
  static const Color backgroundColor = Color(0xFFF0EDE9);

  bool _pushNotifications = true;
  bool _emailNotifications = true;
  bool _rentalReminders = true;
  bool _chatNotifications = true;
  bool _meritAlerts = true;
  bool _darkMode = false;
  String _language = 'English';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        title: const Text('Settings'),
        centerTitle: true,
        leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader('Account'),
            _settingsCard([
              _navTile(Icons.account_circle_outlined, 'Edit Profile',
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(
                          builder: (_) => const EditProfilePage()))),
              _divider(),
              _navTile(Icons.lock_outline, 'Change Password',
                  onTap: () => _showChangePasswordSheet()),
              _divider(),
              _navTile(Icons.email_outlined, 'Change Email',
                  onTap: () {}),
              _divider(),
              _navTile(Icons.phone_outlined, 'Phone Number',
                  onTap: () {}),
            ]),
            const SizedBox(height: 16),

            _sectionHeader('Notifications'),
            _settingsCard([
              _toggleTile(Icons.notifications_outlined,
                  'Push Notifications', _pushNotifications,
                      (v) => setState(() => _pushNotifications = v)),
              _divider(),
              _toggleTile(Icons.email_outlined, 'Email Notifications',
                  _emailNotifications,
                      (v) => setState(() => _emailNotifications = v)),
              _divider(),
              _toggleTile(Icons.schedule, 'Rental Reminders',
                  _rentalReminders,
                      (v) => setState(() => _rentalReminders = v)),
              _divider(),
              _toggleTile(Icons.chat_bubble_outline,
                  'Chat Notifications', _chatNotifications,
                      (v) => setState(() => _chatNotifications = v)),
              _divider(),
              _toggleTile(Icons.military_tech, 'Merit Alerts',
                  _meritAlerts,
                      (v) => setState(() => _meritAlerts = v)),
            ]),
            const SizedBox(height: 16),

            _sectionHeader('Appearance'),
            _settingsCard([
              _toggleTile(Icons.dark_mode_outlined, 'Dark Mode',
                  _darkMode,
                      (v) => setState(() => _darkMode = v)),
              _divider(),
              ListTile(
                leading:
                const Icon(Icons.language, color: Colors.grey),
                title: const Text('Language'),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(_language,
                      style: TextStyle(color: Colors.grey.shade600)),
                  const Icon(Icons.chevron_right, color: Colors.grey),
                ]),
                onTap: () => _showLanguageSheet(),
              ),
            ]),
            const SizedBox(height: 16),

            _sectionHeader('Privacy & Security'),
            _settingsCard([
              _navTile(Icons.visibility_outlined, 'Profile Visibility',
                  onTap: () {}),
              _divider(),
              _navTile(
                  Icons.security, 'Two-Factor Authentication',
                  onTap: () {}),
              _divider(),
              _navTile(Icons.block, 'Blocked Users', onTap: () {}),
              _divider(),
              _navTile(Icons.download_outlined, 'Download My Data',
                  onTap: () {}),
            ]),
            const SizedBox(height: 16),

            _sectionHeader('Support'),
            _settingsCard([
              _navTile(Icons.help_outline, 'Help Center',
                  onTap: () {}),
              _divider(),
              _navTile(Icons.report_outlined, 'Report a Problem',
                  onTap: () {}),
              _divider(),
              _navTile(Icons.star_border, 'Rate the App',
                  onTap: () {}),
              _divider(),
              _navTile(Icons.info_outline, 'About RentalApp',
                  onTap: () => _showAboutDialog()),
            ]),
            const SizedBox(height: 16),

            _sectionHeader('Account Actions'),
            _settingsCard([
              _navTile(Icons.logout, 'Log Out',
                  color: Colors.red, onTap: () async {
                    await SupabaseService.signOut();
                    if (mounted) {
                      Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const LoginScreen()),
                              (_) => false);
                    }
                  }),
              _divider(),
              _navTile(
                  Icons.delete_forever_outlined, 'Delete Account',
                  color: Colors.red,
                  onTap: () => _showDeleteAccountDialog()),
            ]),
            const SizedBox(height: 32),

            Center(
                child: Text('RentalApp v1.0.0',
                    style: TextStyle(
                        color: Colors.grey.shade400, fontSize: 12))),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) => Padding(
    padding: const EdgeInsets.only(bottom: 8, left: 4),
    child: Text(title,
        style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Colors.grey.shade600,
            letterSpacing: 0.5)),
  );

  Widget _settingsCard(List<Widget> children) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [
        BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2))
      ],
    ),
    child: Column(children: children),
  );

  Widget _divider() => const Divider(height: 1, indent: 56);

  Widget _toggleTile(IconData icon, String title, bool value,
      ValueChanged<bool> onChanged) {
    return ListTile(
      leading: Icon(icon, color: primaryColor),
      title: Text(title),
      trailing:
      Switch(value: value, onChanged: onChanged, activeColor: primaryColor),
    );
  }

  Widget _navTile(IconData icon, String title,
      {VoidCallback? onTap, Color? color}) {
    return ListTile(
      leading: Icon(icon, color: color ?? primaryColor),
      title: Text(title, style: TextStyle(color: color)),
      trailing: const Icon(Icons.chevron_right, color: Colors.grey),
      onTap: onTap,
    );
  }

  void _showChangePasswordSheet() {
    final passCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            left: 20,
            right: 20,
            top: 20),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Change Password',
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              TextField(
                  controller: passCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                      labelText: 'New Password',
                      border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(
                  controller: confirmCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                      labelText: 'Confirm Password',
                      border: OutlineInputBorder())),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () {
                    if (passCtrl.text != confirmCtrl.text) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Passwords do not match')));
                      return;
                    }
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text(
                            'Password update requested — check your email.')));
                  },
                  style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12))),
                  child: const Text('Update Password'),
                ),
              ),
              const SizedBox(height: 20),
            ]),
      ),
    );
  }

  void _showLanguageSheet() {
    final languages = ['English', 'বাংলা', 'العربية', 'हिन्दी'];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Column(mainAxisSize: MainAxisSize.min, children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('Select Language',
              style:
              TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ),
        ...languages.map((l) => ListTile(
          title: Text(l),
          trailing: _language == l
              ? const Icon(Icons.check, color: primaryColor)
              : null,
          onTap: () {
            setState(() => _language = l);
            Navigator.pop(context);
          },
        )),
        const SizedBox(height: 16),
      ]),
    );
  }

  void _showAboutDialog() {
    showAboutDialog(
      context: context,
      applicationName: 'RentalApp',
      applicationVersion: '1.0.0',
      applicationIcon:
      const Icon(Icons.home_work, size: 40, color: primaryColor),
      children: [
        const Text('Rent anything, anywhere.\n\n© 2025 RentalApp.')
      ],
    );
  }

  void _showDeleteAccountDialog() {
    showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Delete Account'),
          content: const Text(
              'This action is irreversible. All your data will be permanently deleted.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text(
                        'Please contact support to delete your account.')));
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white),
              child: const Text('Delete'),
            ),
          ],
        ));
  }
}

// ─────────────────────────────────────────────────────────────
// Shared widgets
// ─────────────────────────────────────────────────────────────
class _ProfileCard extends StatelessWidget {
  final String title, subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _ProfileCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child:
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 32, color: color),
            const SizedBox(height: 12),
            Text(title,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(subtitle,
                style: TextStyle(
                    fontSize: 12, color: Colors.grey.shade600)),
          ]),
        ),
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final Color? color;

  const _MenuItem(
      {required this.icon,
        required this.title,
        required this.onTap,
        this.color});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(title, style: TextStyle(color: color)),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

// ─────────────────────────────────────────────────────────────
// UserProfilePage
// View another user's public profile, merit, listings & NID status
// ─────────────────────────────────────────────────────────────
class UserProfilePage extends StatefulWidget {
  final String userId;
  final String? initialName;
  final String? initialAvatar;

  const UserProfilePage({
    super.key,
    required this.userId,
    this.initialName,
    this.initialAvatar,
  });

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> {
  static const Color primaryColor = Color(0xFF381932);
  static const Color backgroundColor = Color(0xFFF0EDE9);

  Map<String, dynamic>? _profile;
  List<Map<String, dynamic>> _listings = [];
  bool _loading = true;
  bool _listingsLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final profile = await SupabaseService.fetchProfile(widget.userId);
      if (mounted) setState(() { _profile = profile; _loading = false; });

      // Fetch this user's listings
      final all = await SupabaseService.fetchProducts();
      final mine = all.where((p) => p['owner_id'] == widget.userId).toList();
      if (mounted) setState(() { _listings = mine; _listingsLoading = false; });
    } catch (_) {
      if (mounted) setState(() { _loading = false; _listingsLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = _profile?['full_name'] as String? ?? widget.initialName ?? 'User';
    final avatar = _profile?['avatar_url'] as String? ?? widget.initialAvatar ?? '';
    final bio = _profile?['bio'] as String? ?? '';
    final phone = _profile?['phone'] as String? ?? '';
    final address = _profile?['address'] as String? ?? '';
    final nidVerified = _profile?['nid_verified'] == true;
    final meritPoints = (_profile?['merit_points'] as num?)?.toInt() ?? 70;
    final isBanned = _profile?['is_banned'] == true;
    final isAdmin = _profile?['is_admin'] == true;

    // Merit tier colour (mirrors MeritService logic)
    Color meritColor;
    String meritLabel;
    if (meritPoints >= 90) { meritColor = const Color(0xFFFFD700); meritLabel = 'Platinum'; }
    else if (meritPoints >= 70) { meritColor = const Color(0xFF2E7D32); meritLabel = 'Good'; }
    else if (meritPoints >= 40) { meritColor = const Color(0xFFFF6F00); meritLabel = 'Fair'; }
    else if (meritPoints >= 20) { meritColor = const Color(0xFFB71C1C); meritLabel = 'Poor'; }
    else { meritColor = const Color(0xFF424242); meritLabel = 'Banned'; }

    final isMe = SupabaseService.currentUserId == widget.userId;

    return Scaffold(
      backgroundColor: backgroundColor,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
        slivers: [
          // ── Collapsible header ──────────────────────────────
          SliverAppBar(
            expandedHeight: 220,
            pinned: true,
            backgroundColor: primaryColor,
            foregroundColor: Colors.white,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.pop(context),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  // Gradient background
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [primaryColor, primaryColor.withOpacity(0.75)],
                      ),
                    ),
                  ),
                  // Avatar centred
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(height: 40),
                        Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: meritColor, width: 3),
                            boxShadow: [BoxShadow(color: meritColor.withOpacity(0.35), blurRadius: 14, spreadRadius: 2)],
                          ),
                          child: CircleAvatar(
                            radius: 48,
                            backgroundImage: avatar.isNotEmpty ? NetworkImage(avatar) : null,
                            backgroundColor: Colors.white24,
                            child: avatar.isEmpty ? const Icon(Icons.person, size: 48, color: Colors.white) : null,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Text(name, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold, shadows: [Shadow(blurRadius: 4, color: Colors.black38)])),
                          if (nidVerified) ...[
                            const SizedBox(width: 6),
                            const Icon(Icons.verified, color: Colors.lightBlueAccent, size: 18),
                          ],
                          if (isAdmin) ...[
                            const SizedBox(width: 6),
                            const Icon(Icons.admin_panel_settings, color: Colors.amber, size: 18),
                          ],
                        ]),
                        if (isBanned)
                          Container(
                            margin: const EdgeInsets.only(top: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                            decoration: BoxDecoration(color: Colors.red.shade700, borderRadius: BorderRadius.circular(12)),
                            child: const Text('BANNED', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  // ── Badges row ──────────────────────────────
                  Wrap(
                    spacing: 8, runSpacing: 8,
                    children: [
                      _badge(
                        icon: nidVerified ? Icons.verified_user : Icons.shield_outlined,
                        label: nidVerified ? 'NID Verified' : 'NID Not Verified',
                        color: nidVerified ? Colors.green : Colors.orange,
                      ),
                      _badge(
                        icon: Icons.military_tech,
                        label: '$meritLabel ($meritPoints pts)',
                        color: meritColor,
                      ),
                      if (isAdmin)
                        _badge(icon: Icons.admin_panel_settings, label: 'Admin', color: Colors.amber),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // ── Bio / Phone ─────────────────────────────
                  if (bio.isNotEmpty) ...[
                    _sectionTitle('About'),
                    _infoCard([
                      _infoRow(Icons.info_outline, bio),
                    ]),
                    const SizedBox(height: 16),
                  ],
                  if (phone.isNotEmpty) ...[
                    _infoCard([
                      _infoRow(Icons.phone_outlined, phone),
                    ]),
                    const SizedBox(height: 16),
                  ],
                  if (address.isNotEmpty) ...[
                    _infoCard([
                      _infoRow(Icons.location_on_outlined, address),
                    ]),
                    const SizedBox(height: 16),
                  ],

                  // ── Merit bar ───────────────────────────────
                  _sectionTitle('Merit Score'),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                          Text(meritLabel, style: TextStyle(fontWeight: FontWeight.bold, color: meritColor, fontSize: 15)),
                          Text('$meritPoints / 100', style: TextStyle(fontWeight: FontWeight.bold, color: meritColor, fontSize: 18)),
                        ]),
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: meritPoints / 100,
                            minHeight: 12,
                            backgroundColor: Colors.grey.shade200,
                            valueColor: AlwaysStoppedAnimation<Color>(meritColor),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          meritPoints >= 70 ? 'This user is trusted and can rent items.' :
                          meritPoints >= 40 ? 'This user has a fair track record.' :
                          'This user has a low merit score — proceed with caution.',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── NID Section ─────────────────────────────
                  _sectionTitle('Identity Verification'),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Icon(
                            nidVerified ? Icons.verified_user : Icons.shield_outlined,
                            color: nidVerified ? Colors.green : Colors.orange,
                            size: 22,
                          ),
                          const SizedBox(width: 10),
                          Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                nidVerified ? 'Identity Verified' : 'Identity Not Verified',
                                style: TextStyle(fontWeight: FontWeight.bold, color: nidVerified ? Colors.green : Colors.orange, fontSize: 15),
                              ),
                              Text(
                                nidVerified ? 'This user has verified their national ID.' : 'This user has not submitted an NID for verification.',
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                              ),
                            ],
                          )),
                        ]),


                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── Listings ────────────────────────────────
                  _sectionTitle('Listings (${_listings.length})'),
                  if (_listingsLoading)
                    const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
                  else if (_listings.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(children: [
                          Icon(Icons.inventory_2_outlined, size: 48, color: Colors.grey.shade400),
                          const SizedBox(height: 8),
                          Text('No listings yet', style: TextStyle(color: Colors.grey.shade500)),
                        ]),
                      ),
                    )
                  else
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        childAspectRatio: 0.75,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                      ),
                      itemCount: _listings.length,
                      itemBuilder: (context, i) {
                        final p = Product.fromMap(_listings[i]);
                        return ProductGridCard(product: p);
                      },
                    ),

                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(t, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
  );

  Widget _badge({required IconData icon, required String label, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Widget _infoCard(List<Widget> children) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))],
    ),
    child: Column(children: children),
  );

  Widget _infoRow(IconData icon, String text) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 18, color: Colors.grey.shade500),
      const SizedBox(width: 10),
      Expanded(child: Text(text, style: const TextStyle(fontSize: 14))),
    ],
  );
}

// ─────────────────────────────────────────────────────────────
// ResetPasswordScreen
// Shown automatically when user clicks the password-reset link
// in their email. main.dart listens for the PASSWORD_RECOVERY
// auth event and navigates here.
// ─────────────────────────────────────────────────────────────
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  static const Color _primary = Color(0xFF381932);

  final _formKey       = GlobalKey<FormState>();
  final _passCtrl      = TextEditingController();
  final _confirmCtrl   = TextEditingController();
  bool _obscurePass    = true;
  bool _obscureConfirm = true;
  bool _loading        = false;
  bool _done           = false;

  @override
  void dispose() {
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await SupabaseService.updatePassword(_passCtrl.text.trim());
      if (mounted) setState(() { _loading = false; _done = true; });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _goToLogin() {
    // Sign out the recovery session then go back to login
    Supabase.instance.client.auth.signOut();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
          (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F0F4),
      appBar: AppBar(
        backgroundColor: _primary,
        foregroundColor: Colors.white,
        title: const Text('Set New Password'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _goToLogin,
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: _done ? _successCard() : _formCard(),
        ),
      ),
    );
  }

  Widget _successCard() {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72, height: 72,
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.check_circle_outline,
                size: 40, color: Colors.green.shade600),
          ),
          const SizedBox(height: 20),
          const Text(
            'Password Updated!',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          Text(
            'Your password has been changed successfully. Please log in with your new password.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _goToLogin,
              style: ElevatedButton.styleFrom(
                backgroundColor: _primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Go to Login',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _formCard() {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon header
            Center(
              child: Container(
                width: 72, height: 72,
                decoration: BoxDecoration(
                  color: _primary.withOpacity(0.08),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.lock_reset, size: 36, color: _primary),
              ),
            ),
            const SizedBox(height: 20),
            const Center(
              child: Text(
                'Create New Password',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                'Your new password must be at least 6 characters.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
            ),
            const SizedBox(height: 28),

            // New password
            const Text('New Password',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 6),
            TextFormField(
              controller: _passCtrl,
              obscureText: _obscurePass,
              decoration: _inputDec(
                'Enter new password',
                Icons.lock_outline,
                suffix: IconButton(
                  icon: Icon(
                    _obscurePass ? Icons.visibility_off : Icons.visibility,
                    color: Colors.grey,
                  ),
                  onPressed: () =>
                      setState(() => _obscurePass = !_obscurePass),
                ),
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Password is required';
                if (v.length < 6) return 'Must be at least 6 characters';
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Confirm password
            const Text('Confirm Password',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 6),
            TextFormField(
              controller: _confirmCtrl,
              obscureText: _obscureConfirm,
              decoration: _inputDec(
                'Confirm new password',
                Icons.lock_outline,
                suffix: IconButton(
                  icon: Icon(
                    _obscureConfirm ? Icons.visibility_off : Icons.visibility,
                    color: Colors.grey,
                  ),
                  onPressed: () =>
                      setState(() => _obscureConfirm = !_obscureConfirm),
                ),
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Please confirm your password';
                if (v != _passCtrl.text) return 'Passwords do not match';
                return null;
              },
            ),
            const SizedBox(height: 28),

            // Submit button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loading ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: _primary.withOpacity(0.5),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: _loading
                    ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
                    : const Text('Update Password',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDec(String hint, IconData icon,
      {Widget? suffix}) =>
      InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, color: Colors.grey),
        suffixIcon: suffix,
        filled: true,
        fillColor: Colors.grey.shade50,
        contentPadding:
        const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _primary, width: 1.5)),
        errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.red)),
        focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.red)),
      );
}