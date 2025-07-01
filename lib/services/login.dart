import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:twitterr/services/auth.dart';

class Login extends StatefulWidget {
  const Login({Key? key}) : super(key: key);

  @override
  _LoginState createState() => _LoginState();
}

class _LoginState extends State<Login> with TickerProviderStateMixin {
  final AuthService _auth = AuthService();
  final _formKey = GlobalKey<FormState>();
  bool isLoading = false;
  bool isGoogleLoading = false;
  bool _obscurePassword = true;
  String email = '';
  String password = '';
  
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

  Future<void> signIn() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        isLoading = true;
      });
      dynamic result = await _auth.signInWithEmailAndPassword(email, password);
      if (result != null) {
        Navigator.pushReplacementNamed(context, '/home');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.error_outline, color: Colors.white),
                SizedBox(width: 12),
                Expanded(child: Text('Authentication failed. Please try again.')),
              ],
            ),
            backgroundColor: Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            margin: EdgeInsets.all(16),
          ),
        );
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  Future<void> signInWithGoogle() async {
    setState(() {
      isGoogleLoading = true;
    });

    try {
      dynamic result = await _auth.signInWithGoogle();
      
      if (result != null) {
        // Success - navigate to home
        Navigator.pushReplacementNamed(context, '/home');
      } else {
        // User cancelled or sign-in failed
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.white),
                SizedBox(width: 12),
                Expanded(child: Text('Google Sign-In was cancelled or failed')),
              ],
            ),
            backgroundColor: Colors.orange.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            margin: EdgeInsets.all(16),
          ),
        );
      }
    } catch (e) {
      // Handle errors
      String errorMessage = 'Google Sign-In failed. Please try again.';
      Color backgroundColor = Colors.red.shade600;
      IconData errorIcon = Icons.error_outline;
      
      if (e.toString().contains('EMAIL_NOT_REGISTERED')) {
        errorMessage = 'This email is not registered. Please create an account first or use a registered email.';
        backgroundColor = Colors.orange.shade600;
        errorIcon = Icons.person_off_outlined;
      } else if (e.toString().contains('not configured') || 
          e.toString().contains('channel-error')) {
        errorMessage = 'Google Sign-In not configured. Please contact admin.';
        backgroundColor = Colors.red.shade600;
        errorIcon = Icons.settings_outlined;
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(errorIcon, color: Colors.white),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  errorMessage,
                  style: TextStyle(fontSize: 14),
                ),
              ),
            ],
          ),
          backgroundColor: backgroundColor,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          margin: EdgeInsets.all(16),
          duration: Duration(seconds: 5),
        ),
      );
    } finally {
      setState(() {
        isGoogleLoading = false;
      });
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
                                         // Animated Logo Container - No Background
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
                                           'Welcome to the future of academic excellence',
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
                               // Glassmorphism Login Card
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
                                                     'Sign In',
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
                                                   'Access your digital campus',
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
                                          // Email Field
                                          _buildGlassFormField(
                                            label: 'University Email',
                                            hint: '2025xxxxxx@xxxxx.uitm.edu.my',
                                            icon: Icons.email_outlined,
                                            onChanged: (val) => setState(() => email = val),
                                            validator: (val) => val!.isEmpty || !val.contains('@')
                                                ? 'Enter a valid university email'
                                                : null,
                                            keyboardType: TextInputType.emailAddress,
                                                                                     ),
                                           const SizedBox(height: 20),
                                           // Password Field
                                          _buildGlassFormField(
                                            label: 'Password',
                                            hint: 'Enter your secure password',
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
                                          const SizedBox(height: 25),
                                           // Sign In Button
                                          _buildGlassButton(
                                            onPressed: isLoading ? null : signIn,
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
                                                      Icon(Icons.login_rounded, color: Colors.white),
                                                      SizedBox(width: 12),
                                                      Text(
                                                        'Sign In to Portal',
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
                                           const SizedBox(height: 20),
                                           // Divider
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Container(
                                                  height: 1,
                                                  decoration: BoxDecoration(
                                                    gradient: LinearGradient(
                                                      colors: [
                                                        Colors.transparent,
                                                        Colors.white.withOpacity(0.3),
                                                        Colors.transparent,
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              Padding(
                                                padding: EdgeInsets.symmetric(horizontal: 20),
                                                child: Text(
                                                  'or continue with',
                                                  style: TextStyle(
                                                    color: Colors.white.withOpacity(0.7),
                                                    fontWeight: FontWeight.w400,
                                                    fontSize: 14,
                                                  ),
                                                ),
                                              ),
                                              Expanded(
                                                child: Container(
                                                  height: 1,
                                                  decoration: BoxDecoration(
                                                    gradient: LinearGradient(
                                                      colors: [
                                                        Colors.transparent,
                                                        Colors.white.withOpacity(0.3),
                                                        Colors.transparent,
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ),
                                                                                       ],
                                           ),
                                           const SizedBox(height: 20),
                                           // Google Button
                                           _buildGoogleButton(),
                                           const SizedBox(height: 30),
                                           // Register Link
                                          Center(
                                            child: TextButton(
                                              onPressed: () {
                                                Navigator.pushNamed(context, '/register');
                                              },
                                              style: TextButton.styleFrom(
                                                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(15),
                                                ),
                                              ),
                                              child: RichText(
                                                text: TextSpan(
                                                  text: 'New to UiTM Portal? ',
                                                  style: TextStyle(
                                                    color: Colors.white.withOpacity(0.8),
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w300,
                                                  ),
                                                  children: [
                                                    TextSpan(
                                                      text: 'Create Account',
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

  Widget _buildGoogleButton() {
    return Container(
      width: double.infinity,
      height: 52,
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
          width: 1.5,
        ),
      ),
      child: OutlinedButton(
        onPressed: isGoogleLoading ? null : signInWithGoogle,
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.transparent,
          side: BorderSide.none,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
                 child: isGoogleLoading
             ? Row(
                 mainAxisAlignment: MainAxisAlignment.center,
                 children: [
                   SizedBox(
                     height: 24,
                     width: 24,
                     child: CircularProgressIndicator(
                       color: Colors.white,
                       strokeWidth: 2.5,
                     ),
                   ),
                   const SizedBox(width: 12),
                   Text(
                     'Signing in...',
                     style: TextStyle(
                       fontSize: 16,
                       fontWeight: FontWeight.w600,
                       color: Colors.white.withOpacity(0.9),
                       letterSpacing: 0.5,
                     ),
                   ),
                 ],
               )
             : Row(
                 mainAxisAlignment: MainAxisAlignment.center,
                 children: [
                   Container(
                     padding: EdgeInsets.all(4),
                     decoration: BoxDecoration(
                       color: Colors.white,
                       borderRadius: BorderRadius.circular(8),
                     ),
                     child: Icon(
                       Icons.g_mobiledata,
                       color: Colors.red,
                       size: 24,
                     ),
                   ),
                   const SizedBox(width: 12),
                   Expanded(
                     child: Column(
                       mainAxisSize: MainAxisSize.min,
                       children: [
                         Text(
                           'Continue with Google',
                           textAlign: TextAlign.center,
                           style: TextStyle(
                             fontSize: 16,
                             fontWeight: FontWeight.w600,
                             color: Colors.white.withOpacity(0.9),
                             letterSpacing: 0.5,
                           ),
                         ),
                         Text(
                           'Existing users only',
                           textAlign: TextAlign.center,
                           style: TextStyle(
                             fontSize: 11,
                             fontWeight: FontWeight.w300,
                             color: Colors.white.withOpacity(0.6),
                             letterSpacing: 0.3,
                           ),
                         ),
                       ],
                     ),
                   ),
                 ],
               ),
      ),
    );
  }
}
