import 'package:dormdevise/pages/home_page.dart';
import 'package:dormdevise/pages/person_page.dart';
import 'package:dormdevise/pages/table_page.dart';
import 'package:flutter/material.dart';
import 'colors.dart';

class ManagementScreen extends StatefulWidget {
  const ManagementScreen({super.key});

  @override
  _ManagementScreenState createState() => _ManagementScreenState();
}

class _ManagementScreenState extends State<ManagementScreen> {
  int selectedIndex = 1;
  final List<Widget> pages = [
    const TablePage(),
    const OpenDoorPage(),
    const PersonPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      resizeToAvoidBottomInset: false,
      bottomNavigationBar: Theme(
        data: Theme.of(context).copyWith(
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
        ),
        child: BottomNavigationBar(
          elevation: 0,
          backgroundColor: kBackground,
          unselectedItemColor: Colors.grey,
          selectedItemColor: Colors.black,
          type: BottomNavigationBarType.fixed,
          currentIndex: selectedIndex,
          onTap: (value) {
            setState(() {
              selectedIndex = value;
            });
          },
          items: [
            BottomNavigationBarItem(
              icon: Icon(
                selectedIndex == 0
                    ? Icons.calendar_today
                    : Icons.calendar_today_outlined,
                size: selectedIndex == 0 ? 28 : 24,
              ),
              label: "",
            ),
            BottomNavigationBarItem(
              icon: Icon(
                selectedIndex == 1
                    ? Icons.door_front_door
                    : Icons.door_front_door_outlined,
                size: selectedIndex == 1 ? 28 : 24,
              ),
              label: "",
            ),
            BottomNavigationBarItem(
              icon: Icon(
                selectedIndex == 2 ? Icons.person : Icons.person_outline,
                size: selectedIndex == 2 ? 28 : 24,
              ),
              label: "",
            ),
          ],
        ),
      ),
      body: GestureDetector(
        onHorizontalDragEnd: (details) {
          if (details.primaryVelocity != null) {
            if (details.primaryVelocity! < 0 &&
                selectedIndex < pages.length - 1) {
              setState(() {
                selectedIndex++;
              });
            } else if (details.primaryVelocity! > 0 && selectedIndex > 0) {
              setState(() {
                selectedIndex--;
              });
            }
          }
        },
        child: pages[selectedIndex],
      ),
    );
  }
}
