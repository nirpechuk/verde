import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../helpers/utils.dart';

class AuthScreen extends StatefulWidget {
  final String? actionContext; // e.g., "to report an issue" or "to create an event"
  final bool isDarkMode;

  const AuthScreen({super.key, this.actionContext, this.isDarkMode = false});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isSignUp = false;
  bool _isLoading = false;
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<void> _authenticate() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text.trim();

      if (_isSignUp) {
        final response = await _supabase.auth.signUp(
          email: email,
          password: password,
          emailRedirectTo: null, // Disable email verification
        );

        if (response.user != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Account created and signed in successfully!'),
              backgroundColor: lightModeMedium,
            ),
          );
          Navigator.pop(context, true); // Return success
        }
      } else {
        final response = await _supabase.auth.signInWithPassword(
          email: email,
          password: password,
        );

        if (response.user != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Signed in successfully!'),
              backgroundColor: lightModeMedium,
            ),
          );
          Navigator.pop(context, true); // Return success
        }
      }
    } on AuthException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('An error occurred: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: widget.isDarkMode ? darkModeDark : Colors.grey[50],
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.actionContext != null) ...[
                      Container(
                        decoration: BoxDecoration(
                          color: widget.isDarkMode
                              ? highlight.withValues(alpha: 0.1)
                              : Colors.black.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: widget.isDarkMode
                                ? highlight.withValues(alpha: 0.3)
                                : lightModeMedium.withValues(alpha: 0.3),
                            width: 1,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Row(
                            children: [
                              Icon(
                                Icons.info,
                                color: widget.isDarkMode ? highlight : lightModeMedium,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Sign in ${widget.actionContext}',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                    color: widget.isDarkMode ? highlight : lightModeDark,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],

                    // App branding
                    Stack(
                      alignment: Alignment.bottomCenter,
                      children: [
                        Image.asset(
                            'lib/images/combinedlogoname.png',
                            height: 240,
                            fit: BoxFit.contain,
                          ),
                        ],
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _emailController,
                      style: TextStyle(
                        color: widget.isDarkMode ? highlight : lightModeDark,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Email',
                        labelStyle: TextStyle(
                          color: widget.isDarkMode ? darkModeMedium : Colors.grey[600],
                        ),
                        border: OutlineInputBorder(
                          borderSide: BorderSide(
                            color: widget.isDarkMode ? darkModeMedium : lightModeMedium,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(
                            color: widget.isDarkMode ? darkModeMedium : lightModeMedium,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(
                            color: widget.isDarkMode ? highlight : lightModeMedium,
                            width: 2,
                          ),
                        ),
                        prefixIcon: Icon(
                          Icons.email,
                          color: widget.isDarkMode ? darkModeMedium : lightModeMedium,
                        ),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter your email';
                        }
                        if (!value.contains('@')) {
                          return 'Please enter a valid email';
                        }
                        return null;
                      },
                    ),

                    const SizedBox(height: 16),

                    TextFormField(
                      controller: _passwordController,
                      style: TextStyle(
                        color: widget.isDarkMode ? highlight : lightModeDark,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Password',
                        labelStyle: TextStyle(
                          color: widget.isDarkMode ? darkModeMedium : Colors.grey[600],
                        ),
                        border: OutlineInputBorder(
                          borderSide: BorderSide(
                            color: widget.isDarkMode ? darkModeMedium : lightModeMedium,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(
                            color: widget.isDarkMode ? darkModeMedium : lightModeMedium,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(
                            color: widget.isDarkMode ? highlight : lightModeMedium,
                            width: 2,
                          ),
                        ),
                        prefixIcon: Icon(
                          Icons.lock,
                          color: widget.isDarkMode ? darkModeMedium : lightModeMedium,
                        ),
                      ),
                      obscureText: true,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter your password';
                        }
                        if (value.length < 6) {
                          return 'Password must be at least 6 characters';
                        }
                        return null;
                      },
                    ),

                    const SizedBox(height: 24),

                    Container(
                      width: double.infinity,
                      height: kFloatingButtonSize,
                      decoration: BoxDecoration(
                        color: widget.isDarkMode
                            ? highlight.withValues(alpha: 0.1)
                            : Colors.black.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(kFloatingButtonBorderRadius),
                        border: Border.all(
                          color: widget.isDarkMode
                              ? highlight.withValues(alpha: 0.3)
                              : lightModeMedium.withValues(alpha: 0.9),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                          BoxShadow(
                            color: (widget.isDarkMode ? highlight : lightModeMedium)
                                .withValues(alpha: 0.1),
                            blurRadius: 10,
                            offset: const Offset(0, 0),
                          ),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(kFloatingButtonBorderRadius),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(kFloatingButtonBorderRadius),
                          onTap: _isLoading ? null : _authenticate,
                          child: Container(
                            width: double.infinity,
                            height: kFloatingButtonSize,
                            alignment: Alignment.center,
                            child: _isLoading
                                ? CircularProgressIndicator(
                                    color: widget.isDarkMode ? highlight : lightModeMedium,
                                  )
                                : Text(
                                    _isSignUp ? 'Create Account' : 'Sign In',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: widget.isDarkMode ? highlight : lightModeMedium,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    TextButton(
                      onPressed: () {
                        setState(() {
                          _isSignUp = !_isSignUp;
                        });
                      },
                      child: Text(
                        _isSignUp
                            ? 'Already have an account? Sign in'
                            : 'Don\'t have an account? Create one',
                        style: TextStyle(
                          color: widget.isDarkMode ? highlight : lightModeMedium,
                        ),
                      ),
                    ),

                    const SizedBox(height: 32),

                    TextButton(
                      onPressed: () {
                        Navigator.pop(context, false); // Return without auth
                      },
                      child: Text(
                        'Continue browsing without account',
                        style: TextStyle(
                          color: widget.isDarkMode ? darkModeMedium : Colors.grey[600],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}
