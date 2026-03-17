import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';
import 'package:intl/intl.dart';

// --- GLOBÁLNÍ NASTAVENÍ APLIKACE ---
// Tohle hlídá změny a říká aplikaci, kdy se má překreslit
class AppSettings extends ChangeNotifier {
  double fontScale = 1.0;
  ThemeMode themeMode = ThemeMode.dark;
  Color seedColor = Colors.orange;

  void updateFontScale(double scale) { fontScale = scale; notifyListeners(); }
  void toggleTheme(bool isDark) { themeMode = isDark ? ThemeMode.dark : ThemeMode.light; notifyListeners(); }
  void changeColor(Color color) { seedColor = color; notifyListeners(); }
}
// Vytvoříme jednu globální instanci, ke které mají přístup všechny obrazovky
final appSettings = AppSettings();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const WorkoutApp());
}

class WorkoutApp extends StatelessWidget {
  const WorkoutApp({super.key});

  @override
  Widget build(BuildContext context) {
    // ListenableBuilder naslouchá našemu appSettings a překreslí MaterialApp při každé změně
    return ListenableBuilder(
      listenable: appSettings,
      builder: (context, child) {
        return MaterialApp(
          title: 'Workout Logger',
          debugShowCheckedModeBanner: false,
          themeMode: appSettings.themeMode,
          // Světlý režim
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: appSettings.seedColor, brightness: Brightness.light),
            useMaterial3: true,
          ),
          // Tmavý režim
          darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: appSettings.seedColor, brightness: Brightness.dark),
            useMaterial3: true,
          ),
          // Tohle kouzlo se postará o globální změnu velikosti písma úplně všude
          builder: (context, child) {
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(appSettings.fontScale)),
              child: child!,
            );
          },
          home: const HomeScreen(),
        );
      },
    );
  }
}

// --- 1. OBRAZOVKA: HISTORIE TRÉNINKŮ ---
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isDescending = true; 

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Můj fitness deník'),
        centerTitle: true,
        actions: [
          PopupMenuButton<bool>(
            icon: const Icon(Icons.sort),
            onSelected: (bool value) => setState(() => _isDescending = value),
            itemBuilder: (context) => [
              const PopupMenuItem(value: true, child: Text('Od nejnovějšího (Sestupně)')),
              const PopupMenuItem(value: false, child: Text('Od nejstaršího (Vzestupně)')),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const SettingsScreen())),
          )
        ],
      ),
      body: StreamBuilder(
        stream: FirebaseFirestore.instance.collection('workouts').orderBy('date', descending: _isDescending).snapshots(),
        builder: (context, AsyncSnapshot<QuerySnapshot> snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text('Žádné tréninky. Klepni na + a začni!'));

          return ListView.builder(
            itemCount: snapshot.data!.docs.length,
            itemBuilder: (context, index) {
              var workoutDoc = snapshot.data!.docs[index];
              var workout = workoutDoc.data() as Map<String, dynamic>;
              var date = (workout['date'] as Timestamp).toDate();
              List exercises = workout['exercises'] ?? [];

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: ExpansionTile(
                  // Univerzální šedá, která ladí se vším a neřeší režimy
                  leading: const Icon(Icons.calendar_today, color: Colors.grey),
                  
                  iconColor: Colors.grey,
                  collapsedIconColor: Colors.grey,
                  
                  title: Text(workout['title'], style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(DateFormat('dd.MM.yyyy - HH:mm').format(date)),
                  children: [
                    ...exercises.map<Widget>((ex) => ListTile(
                      leading: const Icon(Icons.check_circle_outline, size: 18),
                      title: Text(ex['name']),
                      subtitle: Text('${ex['primary']} • ${ex['secondary']}\n${ex['sets'] ?? '?'} sérií × ${ex['reps'] ?? '?'} op. • Pauza: ${ex['rest'] ?? '?'}'),
                      isThreeLine: true,
                      dense: true,
                    )),
                    const Divider(height: 1),
                    OverflowBar(
                      alignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        TextButton.icon(
                          icon: const Icon(Icons.edit, color: Colors.blue),
                          label: const Text('Upravit', style: TextStyle(color: Colors.blue)),
                          onPressed: () {
                            Navigator.push(context, MaterialPageRoute(
                              builder: (context) => AddWorkoutScreen(
                                workoutId: workoutDoc.id, 
                                existingData: workout,
                              ),
                            ));
                          },
                        ),
                        TextButton.icon(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          label: const Text('Smazat', style: TextStyle(color: Colors.red)),
                          onPressed: () {
                            FirebaseFirestore.instance.collection('workouts').doc(workoutDoc.id).delete();
                          },
                        ),
                      ],
                    )
                  ],
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const AddWorkoutScreen())),
        label: const Text('Zapsat trénink'),
        icon: const Icon(Icons.add),
      ),
    );
  }
}

// --- 2. OBRAZOVKA: NASTAVENÍ ---
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Definujeme 5 barev pro náš výběr
    final List<Color> themeColors = [Colors.orange, Colors.blue, Colors.green, Colors.red, Colors.deepPurple];

    return Scaffold(
      appBar: AppBar(title: const Text('Nastavení')),
      // ListenableBuilder tady použijeme, aby se slidery a přepínače hned aktualizovaly
      body: ListenableBuilder(
        listenable: appSettings,
        builder: (context, child) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // 1. Tmavý / Světlý režim
              SwitchListTile(
                title: const Text('Tmavý režim', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('Přepíná mezi tmavým a světlým motivem.'),
                value: appSettings.themeMode == ThemeMode.dark,
                onChanged: (isDark) => appSettings.toggleTheme(isDark),
              ),
              const Divider(height: 40),

              // 2. Velikost písma
              const Text('Velikost písma aplikace:', style: TextStyle(fontWeight: FontWeight.bold)),
              Slider(
                value: appSettings.fontScale,
                min: 0.8,
                max: 1.5,
                divisions: 7,
                label: '${(appSettings.fontScale * 100).toInt()} %',
                onChanged: (val) => appSettings.updateFontScale(val),
              ),
              const Divider(height: 40),

              // 3. Hlavní barva aplikace
              const Text('Hlavní barva aplikace:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 15),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: themeColors.map((color) {
                  bool isSelected = appSettings.seedColor == color;
                  return GestureDetector(
                    onTap: () => appSettings.changeColor(color),
                    child: Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        // Pokud je barva vybraná, uděláme jí tlustý rámeček
                        border: isSelected ? Border.all(color: Colors.white, width: 3) : null,
                        boxShadow: isSelected ? [const BoxShadow(color: Colors.white38, blurRadius: 10)] : null,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          );
        }
      ),
    );
  }
}

// --- 3. OBRAZOVKA: PŘIDÁVÁNÍ / ÚPRAVA TRÉNINKU ---
class AddWorkoutScreen extends StatefulWidget {
  final String? workoutId;
  final Map<String, dynamic>? existingData;

  const AddWorkoutScreen({super.key, this.workoutId, this.existingData});

  @override
  State<AddWorkoutScreen> createState() => _AddWorkoutScreenState();
}

class _AddWorkoutScreenState extends State<AddWorkoutScreen> {
  final TextEditingController _titleController = TextEditingController();
  
  final TextEditingController _setsController = TextEditingController();
  final TextEditingController _repsController = TextEditingController();
  final TextEditingController _restController = TextEditingController(); // Nový ovladač pro pauzu

  List<Map<String, dynamic>> _dbExercises = [];
  List<String> _dbMuscleGroups = [];
  List<Map<String, dynamic>> _addedExercises = [];
  bool _isLoading = true;

  String? _selectedExName;
  late DateTime _selectedDate;

  @override
  void initState() {
    super.initState();
    if (widget.existingData != null) {
      _titleController.text = widget.existingData!['title'] ?? '';
      _selectedDate = (widget.existingData!['date'] as Timestamp).toDate();
      var exList = widget.existingData!['exercises'] as List<dynamic>? ?? [];
      _addedExercises = exList.map((e) => Map<String, dynamic>.from(e)).toList();
    } else {
      _selectedDate = DateTime.now();
    }
    _loadData();
  }

  Future<void> _loadData() async {
    final exSnap = await FirebaseFirestore.instance.collection('exercises').get();
    final groupSnap = await FirebaseFirestore.instance.collection('muscle_groups').get();
    setState(() {
      _dbExercises = exSnap.docs.map((d) => d.data()).toList();
      _dbMuscleGroups = groupSnap.docs.map((d) => d['name'] as String).toList();
      _isLoading = false;
    });
  }

  Future<void> _pickDateTime() async {
    DateTime? pickedDate = await showDatePicker(
      context: context, initialDate: _selectedDate, firstDate: DateTime(2000), lastDate: DateTime(2100),
    );
    if (pickedDate != null) {
      TimeOfDay? pickedTime = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_selectedDate));
      if (pickedTime != null) {
        setState(() {
          _selectedDate = DateTime(pickedDate.year, pickedDate.month, pickedDate.day, pickedTime.hour, pickedTime.minute);
        });
      }
    }
  }

  void _showCustomExerciseDialog() {
    final nameCtrl = TextEditingController();
    final setsDialogCtrl = TextEditingController();
    final repsDialogCtrl = TextEditingController();
    final restDialogCtrl = TextEditingController(); // Políčko pro pauzu v dialogu
    
    String p = _dbMuscleGroups.isNotEmpty ? _dbMuscleGroups.first : '';
    String s = _dbMuscleGroups.isNotEmpty ? _dbMuscleGroups.first : '';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Vlastní cvik'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Název cviku')),
                DropdownButtonFormField<String>(
                  value: p.isNotEmpty ? p : null, decoration: const InputDecoration(labelText: 'Hlavní partie'),
                  items: _dbMuscleGroups.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                  onChanged: (v) => setDialogState(() => p = v!),
                ),
                DropdownButtonFormField<String>(
                  value: s.isNotEmpty ? s : null, decoration: const InputDecoration(labelText: 'Vedlejší partie'),
                  items: _dbMuscleGroups.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                  onChanged: (v) => setDialogState(() => s = v!),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: TextField(controller: setsDialogCtrl, decoration: const InputDecoration(labelText: 'Série'), keyboardType: TextInputType.number)),
                    const SizedBox(width: 10),
                    Expanded(child: TextField(controller: repsDialogCtrl, decoration: const InputDecoration(labelText: 'Opak.'))),
                    const SizedBox(width: 10),
                    Expanded(child: TextField(controller: restDialogCtrl, decoration: const InputDecoration(labelText: 'Pauza'))),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Zrušit')),
            ElevatedButton(
              onPressed: () async {
                if (nameCtrl.text.isEmpty || setsDialogCtrl.text.isEmpty || repsDialogCtrl.text.isEmpty) return;
                
                // 1. Uložíme nový cvik natrvalo do Firebase (do kolekce cviků)
                await FirebaseFirestore.instance.collection('exercises').add({
                  'name': nameCtrl.text,
                  'primary': p,
                  'secondary': s,
                });

                setState(() {
                  // 2. Přidáme ho do aktuálně skládaného tréninku
                  _addedExercises.add({
                    'name': nameCtrl.text, 'primary': p, 'secondary': s,
                    'sets': setsDialogCtrl.text, 'reps': repsDialogCtrl.text,
                    'rest': restDialogCtrl.text.isEmpty ? '-' : restDialogCtrl.text // Kdyby pauzu nevyplnil
                  });
                  // 3. Rovnou ho střelíme i do lokálního seznamu, aby byl hned vidět v Dropdownu
                  _dbExercises.add({'name': nameCtrl.text, 'primary': p, 'secondary': s});
                });
                
                if (mounted) Navigator.pop(context);
              },
              child: const Text('Uložit a přidat'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    bool isEditing = widget.workoutId != null;

    return Scaffold(
      appBar: AppBar(title: Text(isEditing ? 'Upravit záznam' : 'Nový záznam')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(controller: _titleController, decoration: const InputDecoration(labelText: 'Název tréninku', border: OutlineInputBorder())),
            const SizedBox(height: 15),
            ListTile(
              contentPadding: EdgeInsets.zero, leading: const Icon(Icons.access_time),
              title: Text('Kdy: ${DateFormat('dd.MM.yyyy - HH:mm').format(_selectedDate)}'),
              trailing: OutlinedButton(onPressed: _pickDateTime, child: const Text('Změnit čas')),
            ),
            const Divider(height: 30),
            
            const Text('Přidat cvik z databáze:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: _selectedExName, isExpanded: true,
              decoration: const InputDecoration(labelText: 'Vyber cvik', border: OutlineInputBorder()),
              items: _dbExercises.map((e) => DropdownMenuItem(
                value: e['name'] as String,
                child: Text('${e['name']} (${e['primary']} • ${e['secondary']})'),
              )).toList(),
              onChanged: (v) => setState(() => _selectedExName = v),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: TextField(controller: _setsController, decoration: const InputDecoration(labelText: 'Série', border: OutlineInputBorder()), keyboardType: TextInputType.number)),
                const SizedBox(width: 10),
                Expanded(child: TextField(controller: _repsController, decoration: const InputDecoration(labelText: 'Opakování', border: OutlineInputBorder()))),
                const SizedBox(width: 10),
                Expanded(child: TextField(controller: _restController, decoration: const InputDecoration(labelText: 'Pauza', border: OutlineInputBorder()))),
              ],
            ),
            const SizedBox(height: 10),
            Center(
              child: ElevatedButton.icon(
                onPressed: () {
                  if (_selectedExName == null || _setsController.text.isEmpty || _repsController.text.isEmpty) return;
                  final exInfo = _dbExercises.firstWhere((e) => e['name'] == _selectedExName);
                  setState(() {
                    _addedExercises.add({
                      'name': exInfo['name'], 'primary': exInfo['primary'], 'secondary': exInfo['secondary'],
                      'sets': _setsController.text, 'reps': _repsController.text,
                      'rest': _restController.text.isEmpty ? '-' : _restController.text
                    });
                    _setsController.clear();
                    _repsController.clear();
                    _restController.clear();
                    _selectedExName = null;
                  });
                },
                icon: const Icon(Icons.add),
                label: const Text('Přidat cvik do tréninku'),
              ),
            ),
            
            Center(
              child: TextButton.icon(
                onPressed: _showCustomExerciseDialog,
                icon: const Icon(Icons.edit), label: const Text('Nebo vytvořit vlastní cvik'),
              ),
            ),

            const Divider(height: 40),
            const Text('Cviky v tomto tréninku:', style: TextStyle(fontWeight: FontWeight.bold)),
            ListView.builder(
              shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
              itemCount: _addedExercises.length,
              itemBuilder: (context, i) => ListTile(
                title: Text(_addedExercises[i]['name']!),
                subtitle: Text('${_addedExercises[i]['primary']} • ${_addedExercises[i]['secondary']}\n${_addedExercises[i]['sets']} sérií × ${_addedExercises[i]['reps']} op. • Pauza: ${_addedExercises[i]['rest']}'),
                isThreeLine: true,
                trailing: IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => setState(() => _addedExercises.removeAt(i))),
              ),
            ),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity, height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: appSettings.seedColor, foregroundColor: Colors.white),
                onPressed: () async {
                  if (_titleController.text.isEmpty || _addedExercises.isEmpty) return;
                  final workoutData = {'title': _titleController.text, 'date': _selectedDate, 'exercises': _addedExercises};
                  if (isEditing) {
                    await FirebaseFirestore.instance.collection('workouts').doc(widget.workoutId).update(workoutData);
                  } else {
                    await FirebaseFirestore.instance.collection('workouts').add(workoutData);
                  }
                  if (mounted) Navigator.pop(context);
                },
                child: Text(isEditing ? 'ULOŽIT ZMĚNY' : 'ULOŽIT TRÉNINK DO CLOUDU', style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            )
          ],
        ),
      ),
    );
  }
}