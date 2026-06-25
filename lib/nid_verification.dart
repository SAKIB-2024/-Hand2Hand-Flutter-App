import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'supabase_service.dart';

class NIDVerificationPage extends StatefulWidget {
  const NIDVerificationPage({super.key});

  @override
  State<NIDVerificationPage> createState() => _NIDVerificationPageState();
}

class _NIDVerificationPageState extends State<NIDVerificationPage> {
  static const Color primaryColor = Color(0xFF381932);
  static const Color backgroundColor = Color(0xFFF0EDE9);

  // Use bytes instead of File — works on Web & Mobile
  Uint8List? _frontBytes;
  Uint8List? _backBytes;

  bool _uploading = false;
  bool _isVerified = false;
  bool _hasRequested = false;
  String? _rejectionReason;
  Map<String, dynamic>? _profile;

  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadVerificationStatus();
  }

  Future<void> _loadVerificationStatus() async {
    final uid = SupabaseService.currentUserId;
    if (uid == null) return;
    final profile = await SupabaseService.fetchProfile(uid);
    if (mounted) {
      setState(() {
        _profile = profile;
        _isVerified = profile?['nid_verified'] == true;
        _hasRequested = profile?['nid_front_url'] != null;
        _rejectionReason = profile?['verification_rejected_reason'];
      });
    }
  }

  Future<void> _pickImage(bool isFront) async {
    final XFile? picked = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (picked != null) {
      final bytes = await picked.readAsBytes();
      setState(() {
        if (isFront) {
          _frontBytes = bytes;
        } else {
          _backBytes = bytes;
        }
      });
    }
  }

  Future<void> _submitVerification() async {
    if (_frontBytes == null || _backBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select both sides of your NID card')),
      );
      return;
    }

    final uid = SupabaseService.currentUserId;
    if (uid == null) return;

    setState(() => _uploading = true);
    try {
      await SupabaseService.uploadNIDImages(uid, _frontBytes!, _backBytes!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Verification request submitted! Admin will review shortly.')),
        );
        await _loadVerificationStatus();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        title: const Text('NID Verification'),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _isVerified
                    ? Colors.green.shade50
                    : (_hasRequested ? Colors.orange.shade50 : Colors.grey.shade50),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _isVerified
                      ? Colors.green
                      : (_hasRequested ? Colors.orange : Colors.grey),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _isVerified
                        ? Icons.verified
                        : (_hasRequested ? Icons.pending : Icons.warning),
                    color: _isVerified
                        ? Colors.green
                        : (_hasRequested ? Colors.orange : Colors.grey),
                    size: 32,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isVerified
                              ? 'Verified Account'
                              : (_hasRequested
                              ? 'Verification Pending'
                              : 'Not Verified'),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: _isVerified
                                ? Colors.green
                                : (_hasRequested
                                ? Colors.orange
                                : Colors.grey.shade700),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _isVerified
                              ? 'Your NID has been verified. You can now sell, buy, and rent items.'
                              : (_hasRequested
                              ? 'Your verification request is being reviewed by an admin.'
                              : 'Verify your NID to unlock all features (sell, buy, rent items)'),
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                        if (_rejectionReason != null && !_hasRequested) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.error_outline,
                                    color: Colors.red.shade700, size: 16),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Rejected: $_rejectionReason',
                                    style: TextStyle(
                                        fontSize: 12, color: Colors.red.shade700),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),

            if (!_isVerified && !_hasRequested) ...[
              const SizedBox(height: 24),
              const Text('Why verify?',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              _benefitItem(Icons.shopping_bag, 'List items for sale or rent'),
              const SizedBox(height: 8),
              _benefitItem(Icons.shopping_cart, 'Purchase items from others'),
              const SizedBox(height: 8),
              _benefitItem(Icons.verified_user, 'Build trust with other users'),
              const SizedBox(height: 8),
              _benefitItem(Icons.security, 'Secure your account'),

              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 16),

              const Text('Upload NID Card',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text(
                'Please upload clear photos of both sides of your NID card.',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 20),

              _imagePickerCard(
                title: 'Front Side',
                imageBytes: _frontBytes,
                onTap: () => _pickImage(true),
              ),
              const SizedBox(height: 16),

              _imagePickerCard(
                title: 'Back Side',
                imageBytes: _backBytes,
                onTap: () => _pickImage(false),
              ),
              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: _uploading ? null : _submitVerification,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _uploading
                      ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(Colors.white)),
                  )
                      : const Text('Submit for Verification',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],

            if (_hasRequested && !_isVerified) ...[
              const SizedBox(height: 32),
              Center(
                child: Column(
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(
                      'Your verification is being reviewed',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'This usually takes 24-48 hours',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _benefitItem(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: primaryColor),
          const SizedBox(width: 12),
          Text(text, style: const TextStyle(fontSize: 14)),
        ],
      ),
    );
  }

  Widget _imagePickerCard({
    required String title,
    required Uint8List? imageBytes,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 180,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
        ),
        // Use Image.memory(bytes) — works on Web AND Mobile
        child: imageBytes != null
            ? ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.memory(imageBytes, fit: BoxFit.cover),
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle, color: Colors.green, size: 16),
                      SizedBox(width: 4),
                      Text('Selected',
                          style: TextStyle(color: Colors.white, fontSize: 10)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        )
            : Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.upload_file, size: 48, color: Colors.grey),
            const SizedBox(height: 8),
            Text(
              'Tap to upload $title',
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 4),
            Text(
              'JPG, PNG',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
            ),
          ],
        ),
      ),
    );
  }
}