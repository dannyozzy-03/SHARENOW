import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:twitterr/services/auth.dart';

class Register extends StatefulWidget {
  const Register({Key? key}) : super(key: key);

  @override
  _RegisterState createState() => _RegisterState();
}

class _RegisterState extends State<Register> with TickerProviderStateMixin {
  final AuthService _auth = AuthService();
  final _formKey = GlobalKey<FormState>();
  bool isLoading = false;
  bool _obscurePassword = true;
  String email = '';
  String password = '';
  String name = '';
  String role = 'Student'; // Default role, will be auto-determined
  bool isEmailValid = false;

  late AnimationController _animationController;
  late AnimationController _floatingController;
  late AnimationController _pulseController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _slideAnimation;
  late Animation<double> _floatingAnimation;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: Duration(milliseconds: 1500),
      vsync: this,
    );
    _floatingController = AnimationController(
      duration: Duration(seconds: 3),
      vsync: this,
    )..repeat(reverse: true);
    _pulseController = AnimationController(
      duration: Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);
    
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _slideAnimation = Tween<double>(begin: 100.0, end: 0.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutBack),
    );
    _floatingAnimation = Tween<double>(begin: -10.0, end: 10.0).animate(
      CurvedAnimation(parent: _floatingController, curve: Curves.easeInOut),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _floatingController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  // Auto-determine role based on email domain
  String determineRoleFromEmail(String email) {
    if (email.trim().endsWith('@student.uitm.edu.my')) {
      return 'Student';
    } else if (email.trim().endsWith('@lecturer.uitm.edu.my') || email.trim().endsWith('@staff.uitm.edu.my')) {
      return 'Lecturer';
    } else if (email.trim().endsWith('@admin.uitm.edu.my')) {
      return 'Admin';
    }
    return 'Student'; // Default fallback
  }

  Future<void> createAccount() async {
    if (_formKey.currentState!.validate()) {
      if (!isEmailValid) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.error_outline, color: Colors.white),
                SizedBox(width: 12),
                Expanded(child: Text('Please enter a valid UiTM email (student/staff).')),
              ],
            ),
            backgroundColor: Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            margin: EdgeInsets.all(16),
          ),
        );
        return;
      }

      setState(() {
        isLoading = true;
      });

      try {
        dynamic result = await _auth.registerWithEmailAndPassword(
            email, password, name, role);

        if (result != null) {
          if (email.endsWith('danish@admin.uitm.edu.my') || email.endsWith('waiz@lecturer.uitm.edu.my')) {
            // Skip email verification for admin and lecturer users
            await saveUserToFirestore(result);
          } else {
            // Send email verification
            await result.sendEmailVerification();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    Icon(Icons.email_outlined, color: Colors.white),
                    SizedBox(width: 12),
                    Expanded(child: Text('A verification email has been sent. Please check your email to verify your account.')),
                  ],
                ),
                backgroundColor: Colors.blue.shade600,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                margin: EdgeInsets.all(16),
              ),
            );

            // Wait for email verification before saving in Firestore
            await checkEmailVerification(result);
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(Icons.error_outline, color: Colors.white),
                  SizedBox(width: 12),
                  Expanded(child: Text('Failed to sign up')),
                ],
              ),
              backgroundColor: Colors.red.shade600,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              margin: EdgeInsets.all(16),
            ),
          );
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.error_outline, color: Colors.white),
                SizedBox(width: 12),
                Expanded(child: Text('Error: ${e.toString()}')),
              ],
            ),
            backgroundColor: Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            margin: EdgeInsets.all(16),
          ),
        );
      }

      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> saveUserToFirestore(User user) async {
    List<String> keywords = generateSearchKeywords(name);

    await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
      'lowercaseName': name.toLowerCase(),
      'searchKeywords': keywords,
      'name': name,
      'email': email,
      'role': role,
      'phoneNumber': null,
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle_outline, color: Colors.white),
            SizedBox(width: 12),
            Expanded(child: Text('Account created successfully!')),
          ],
        ),
        backgroundColor: Colors.green.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: EdgeInsets.all(16),
      ),
    );

    Navigator.pushReplacementNamed(context, '/login');
  }

  bool validateEmail(String email) {
    // Bypass validation for admin emails
    if (email.trim().endsWith('@admin.uitm.edu.my') || email.trim().endsWith('waiz@lecturer.uitm.edu.my')) {
      return true;
    }

    // Check if email is a valid UiTM student/staff email
    final RegExp regex = RegExp(
        r'^[a-zA-Z0-9._%+-]+@(student\.uitm\.edu\.my|staff\.uitm\.edu\.my|lecturer\.uitm\.edu\.my)$');

    return regex.hasMatch(email);
  }

  // Function to Update Email Validation State and Auto-determine Role
  void onEmailChanged(String value) {
    setState(() {
      email = value.trim(); // Trim to remove extra spaces
      isEmailValid = validateEmail(email);
      if (isEmailValid) {
        role = determineRoleFromEmail(email); // Auto-determine role
      }
    });
  }

  List<String> generateSearchKeywords(String name) {
    List<String> keywords = [];
    String temp = "";
    for (int i = 0; i < name.length; i++) {
      temp += name[i].toLowerCase();
      keywords.add(temp);
    }
    return keywords;
  }

  Future<void> checkEmailVerification(User user) async {
    await user.reload();
    user = FirebaseAuth.instance.currentUser!;

    if (user.emailVerified) {
      // Generate search keywords
      List<String> keywords = generateSearchKeywords(name);
      // Save user details in Firestore only after verification
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'lowercaseName': name.toLowerCase(),
        'searchKeywords': keywords,
        'name': name,
        'email': email,
        'role': role,
        'phoneNumber': null,
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle_outline, color: Colors.white),
              SizedBox(width: 12),
              Expanded(child: Text('Email verified! Account created successfully.')),
            ],
          ),
          backgroundColor: Colors.green.shade600,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          margin: EdgeInsets.all(16),
        ),
      );

      // Navigate to login page
      Navigator.pushReplacementNamed(context, '/login');
    } else {
      // If not verified, show a dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return AlertDialog(
            backgroundColor: Colors.white.withOpacity(0.95),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text('Email Not Verified'),
            content: Text('Please verify your email before continuing.'),
            actions: [
              TextButton(
                onPressed: () async {
                  await user.reload();
                  user = FirebaseAuth.instance.currentUser!;
                  if (user.emailVerified) {
                    Navigator.pop(context);
                    checkEmailVerification(user);
                  }
                },
                child: Text('I have verified'),
              ),
              TextButton(
                onPressed: () {
                  FirebaseAuth.instance.signOut();
                  Navigator.pop(context);
                },
                child: Text('Cancel'),
              ),
            ],
          );
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF667eea),
              Color(0xFF764ba2),
              Color(0xFF6B73FF),
              Color(0xFF000428),
            ],
            stops: [0.0, 0.3, 0.7, 1.0],
          ),
        ),
        child: Stack(
          children: [
            // Animated Background Elements
            ...List.generate(6, (index) => AnimatedBuilder(
              animation: _floatingController,
              builder: (context, child) {
                return Positioned(
                  top: 100 + (index * 120) + _floatingAnimation.value,
                  left: (index % 2 == 0 ? -50 : MediaQuery.of(context).size.width - 50) + 
                        math.sin(_floatingController.value * 2 * math.pi + index) * 30,
                  child: Container(
                    width: 100 + (index * 20),
                    height: 100 + (index * 20),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          Colors.white.withOpacity(0.1),
                          Colors.white.withOpacity(0.05),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                );
              },
            )),
            
            // Main Content
            SafeArea(
              child: AnimatedBuilder(
                animation: _animationController,
                builder: (context, child) {
                  return Transform.translate(
                    offset: Offset(0, _slideAnimation.value),
                    child: Opacity(
                      opacity: _fadeAnimation.value,
                      child: SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16),
                          child: Column(
                            children: [
                              const SizedBox(height: 20),
                              // Floating Logo Section
                              AnimatedBuilder(
                                animation: _floatingController,
                                builder: (context, child) {
                                  return Transform.translate(
                                    offset: Offset(0, _floatingAnimation.value * 0.5),
                                    child: Column(
                                      children: [
                                        // Animated Logo Container
                                        AnimatedBuilder(
                                          animation: _pulseController,
                                          builder: (context, child) {
                                            return Transform.scale(
                                              scale: _pulseAnimation.value,
                                              child: Container(
                                                height: 90,
                                                width: 90,
                                                decoration: BoxDecoration(
                                                  borderRadius: BorderRadius.circular(20),
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: Colors.black.withOpacity(0.3),
                                                      blurRadius: 15,
                                                      offset: Offset(0, 8),
                                                    ),
                                                  ],
                                                ),
                                                child: ClipRRect(
                                                  borderRadius: BorderRadius.circular(20),
                                                  child: Image.asset(
                                                    'assets/images/uitm logo.png',
                                                    fit: BoxFit.contain,
                                                    errorBuilder: (context, error, stackTrace) {
                                                      return Container(
                                                        decoration: BoxDecoration(
                                                          gradient: LinearGradient(
                                                            colors: [
                                                              Color(0xFF667eea),
                                                              Color(0xFF764ba2),
                                                            ],
                                                          ),
                                                          borderRadius: BorderRadius.circular(20),
                                                        ),
                                                        child: Icon(
                                                          Icons.school_rounded,
                                                          color: Colors.white,
                                                          size: 45,
                                                        ),
                                                      );
                                                    },
                                                  ),
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                        const SizedBox(height: 16),
                                        ShaderMask(
                                          shaderCallback: (bounds) => LinearGradient(
                                            colors: [Colors.white, Colors.white.withOpacity(0.8)],
                                          ).createShader(bounds),
                                          child: Text(
                                            'ShareNow UiTM Portal',
                                            style: TextStyle(
                                              fontSize: 24,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white,
                                              letterSpacing: 1.2,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          'Join our academic community',
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: Colors.white.withOpacity(0.9),
                                            fontWeight: FontWeight.w300,
                                            letterSpacing: 0.5,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(height: 30),
                              // Glassmorphism Register Card
                              Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(35),
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      Colors.white.withOpacity(0.25),
                                      Colors.white.withOpacity(0.1),
                                    ],
                                  ),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.2),
                                    width: 1.5,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.1),
                                      blurRadius: 40,
                                      offset: Offset(0, 20),
                                    ),
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(35),
                                  child: Container(
                                    padding: const EdgeInsets.all(28),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: [
                                          Colors.white.withOpacity(0.2),
                                          Colors.white.withOpacity(0.1),
                                        ],
                                      ),
                                    ),
                                    child: Form(
                                      key: _formKey,
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          // Header
                                          Center(
                                            child: Column(
                                              children: [
                                                ShaderMask(
                                                  shaderCallback: (bounds) => LinearGradient(
                                                    colors: [Colors.white, Colors.white.withOpacity(0.8)],
                                                  ).createShader(bounds),
                                                  child: Text(
                                                    'Create Account',
                                                    style: TextStyle(
                                                      fontSize: 30,
                                                      fontWeight: FontWeight.bold,
                                                      color: Colors.white,
                                                      letterSpacing: 1.2,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(height: 6),
                                                Text(
                                                  'Join the digital campus community',
                                                  style: TextStyle(
                                                    fontSize: 14,
                                                    color: Colors.white.withOpacity(0.8),
                                                    fontWeight: FontWeight.w300,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(height: 28),
                                          // Full Name Field
                                          _buildGlassFormField(
                                            label: 'Full Name(via IC)',
                                            hint: 'Enter your full name(via IC)',
                                            icon: Icons.person_outline_rounded,
                                            onChanged: (val) => setState(() => name = val),
                                            validator: (val) => val!.isEmpty ? 'Enter your full name(via IC)' : null,
                                            keyboardType: TextInputType.name,
                                          ),
                                          const SizedBox(height: 20),
                                          // Email Field
                                          _buildGlassFormField(
                                            label: 'University Email',
                                            hint: '2025xxxxx@student.uitm.edu.my',
                                            icon: Icons.email_outlined,
                                            onChanged: onEmailChanged,
                                            validator: (val) {
                                              if (!validateEmail(val ?? "")) {
                                                return 'Enter a valid UiTM email or use "@admin".';
                                              }
                                              return null;
                                            },
                                            keyboardType: TextInputType.emailAddress,
                                            suffixIcon: AnimatedSwitcher(
                                              duration: Duration(milliseconds: 300),
                                              child: isEmailValid
                                                  ? Icon(Icons.check_circle,
                                                      color: Colors.green, key: ValueKey(1))
                                                  : Icon(Icons.cancel,
                                                      color: Colors.red.withOpacity(0.7), key: ValueKey(2)),
                                            ),
                                          ),
                                          const SizedBox(height: 20),
                                          // Auto-determined Role Display
                                          if (isEmailValid)
                                            Container(
                                              width: double.infinity,
                                              padding: EdgeInsets.all(16),
                                              decoration: BoxDecoration(
                                                borderRadius: BorderRadius.circular(20),
                                                gradient: LinearGradient(
                                                  begin: Alignment.topLeft,
                                                  end: Alignment.bottomRight,
                                                  colors: [
                                                    Colors.green.withOpacity(0.15),
                                                    Colors.green.withOpacity(0.05),
                                                  ],
                                                ),
                                                border: Border.all(
                                                  color: Colors.green.withOpacity(0.3),
                                                  width: 1,
                                                ),
                                              ),
                                              child: Row(
                                                children: [
                                                  Container(
                                                    margin: EdgeInsets.only(right: 12),
                                                    decoration: BoxDecoration(
                                                      borderRadius: BorderRadius.circular(12),
                                                      gradient: LinearGradient(
                                                        colors: [
                                                          Colors.green.withOpacity(0.2),
                                                          Colors.green.withOpacity(0.1),
                                                        ],
                                                      ),
                                                    ),
                                                    child: Icon(
                                                      Icons.admin_panel_settings,
                                                      color: Colors.green.withOpacity(0.8),
                                                      size: 22,
                                                    ),
                                                  ),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
                                                        Text(
                                                          'Role: $role',
                                                          style: TextStyle(
                                                            fontSize: 16,
                                                            fontWeight: FontWeight.w600,
                                                            color: Colors.white.withOpacity(0.9),
                                                          ),
                                                        ),
                                                        Text(
                                                          'Auto-detected from email domain',
                                                          style: TextStyle(
                                                            fontSize: 12,
                                                            color: Colors.white.withOpacity(0.7),
                                                            fontWeight: FontWeight.w300,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          if (isEmailValid) const SizedBox(height: 20),
                                          // Password Field
                                          _buildGlassFormField(
                                            label: 'Password',
                                            hint: 'Minimum 6 characters',
                                            icon: Icons.lock_outline_rounded,
                                            obscureText: _obscurePassword,
                                            onChanged: (val) => setState(() => password = val),
                                            validator: (val) => val!.length < 6
                                                ? 'Password must be at least 6 characters'
                                                : null,
                                            suffixIcon: IconButton(
                                              icon: Icon(
                                                _obscurePassword
                                                    ? Icons.visibility_off_outlined
                                                    : Icons.visibility_outlined,
                                                color: Colors.white.withOpacity(0.7),
                                              ),
                                              onPressed: () {
                                                setState(() {
                                                  _obscurePassword = !_obscurePassword;
                                                });
                                              },
                                            ),
                                          ),
                                          const SizedBox(height: 30),
                                          // Create Account Button
                                          _buildGlassButton(
                                            onPressed: isLoading ? null : createAccount,
                                            child: isLoading
                                                ? SizedBox(
                                                    height: 24,
                                                    width: 24,
                                                    child: CircularProgressIndicator(
                                                      color: Colors.white,
                                                      strokeWidth: 2.5,
                                                    ),
                                                  )
                                                : Row(
                                                    mainAxisAlignment: MainAxisAlignment.center,
                                                    children: [
                                                      Icon(Icons.person_add_rounded, color: Colors.white),
                                                      SizedBox(width: 12),
                                                      Text(
                                                        'Create Account',
                                                        style: TextStyle(
                                                          fontSize: 18,
                                                          fontWeight: FontWeight.bold,
                                                          color: Colors.white,
                                                          letterSpacing: 1,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                          ),
                                          const SizedBox(height: 30),
                                          // Login Link
                                          Center(
                                            child: TextButton(
                                              onPressed: () {
                                                Navigator.pushNamed(context, '/login');
                                              },
                                              style: TextButton.styleFrom(
                                                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(15),
                                                ),
                                              ),
                                              child: RichText(
                                                text: TextSpan(
                                                  text: 'Already have an account? ',
                                                  style: TextStyle(
                                                    color: Colors.white.withOpacity(0.8),
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w300,
                                                  ),
                                                  children: [
                                                    TextSpan(
                                                      text: 'Sign In',
                                                      style: TextStyle(
                                                        color: Colors.white,
                                                        fontWeight: FontWeight.bold,
                                                        fontSize: 16,
                                                      ),
                                                    ),
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
                              ),
                              const SizedBox(height: 20),
                            ],
                          ),
                        ),
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

  Widget _buildGlassFormField({
    required String label,
    required String hint,
    required IconData icon,
    required Function(String) onChanged,
    required String? Function(String?) validator,
    bool obscureText = false,
    Widget? suffixIcon,
    TextInputType? keyboardType,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.white.withOpacity(0.9),
              letterSpacing: 0.5,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withOpacity(0.15),
                Colors.white.withOpacity(0.05),
              ],
            ),
            border: Border.all(
              color: Colors.white.withOpacity(0.2),
              width: 1,
            ),
          ),
          child: TextFormField(
            onChanged: onChanged,
            validator: validator,
            obscureText: obscureText,
            keyboardType: keyboardType,
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w400,
            ),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 16,
                fontWeight: FontWeight.w300,
              ),
              prefixIcon: Container(
                margin: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: LinearGradient(
                    colors: [
                      Colors.white.withOpacity(0.2),
                      Colors.white.withOpacity(0.1),
                    ],
                  ),
                ),
                child: Icon(
                  icon,
                  color: Colors.white.withOpacity(0.8),
                  size: 22,
                ),
              ),
              suffixIcon: suffixIcon,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: BorderSide.none,
              ),
              contentPadding: EdgeInsets.symmetric(vertical: 16, horizontal: 20),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGlassButton({
    required VoidCallback? onPressed,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      height: 52,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withOpacity(0.3),
            Colors.white.withOpacity(0.1),
          ],
        ),
        border: Border.all(
          color: Colors.white.withOpacity(0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        child: child,
      ),
    );
  }

}
