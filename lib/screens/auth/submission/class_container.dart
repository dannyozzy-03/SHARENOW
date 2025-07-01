import 'package:flutter/material.dart';
import 'package:twitterr/screens/auth/submission/class.dart';
import 'package:twitterr/screens/auth/submission/classwork.dart';
import 'package:twitterr/screens/auth/submission/participants.dart';

class ClassContainer extends StatefulWidget {
  final String classId;
  final String className;

  const ClassContainer({
    Key? key,
    required this.classId,
    required this.className,
  }) : super(key: key);

  @override
  State<ClassContainer> createState() => _ClassContainerState();
}

class _ClassContainerState extends State<ClassContainer> {
  late PageController _pageController;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _changePage(int page) {
    setState(() {
      _currentPage = page;
      _pageController.animateToPage(
        page,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView(
        controller: _pageController,
        onPageChanged: (index) {
          setState(() {
            _currentPage = index;
          });
        },
        children: [
          ClassPage(
            classId: widget.classId,
            className: widget.className,
            onPageChange: _changePage,
          ),
          Classwork(
            classId: widget.classId,
            className: widget.className,
            onPageChange: _changePage,
          ),
          Participants(
            classId: widget.classId,
            className: widget.className,
            onPageChange: _changePage,
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: const Color(0xFF202124),
        selectedItemColor: Colors.white,
        unselectedItemColor: Colors.grey,
        currentIndex: _currentPage,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.forum_outlined),
            label: 'Stream',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.assignment_outlined),
            label: 'Classwork',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.people_outline),
            label: 'Participants',
          ),
        ],
        onTap: _changePage,
      ),
    );
  }
}

class ClassPage extends StatefulWidget {
  final String classId;
  final String className;
  final Function(int) onPageChange;

  const ClassPage({
    Key? key,
    required this.classId,
    required this.className,
    required this.onPageChange,
  }) : super(key: key);

  @override
  State<ClassPage> createState() => _ClassPageState();
}

class _ClassPageState extends State<ClassPage> {
  @override
  Widget build(BuildContext context) {
    return Container();
  }
}
