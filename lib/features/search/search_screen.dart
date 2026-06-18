import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../core/config/env.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/receipt.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Assistant'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(icon: Icon(Icons.smart_toy_outlined), text: 'Ask AI'),
            Tab(icon: Icon(Icons.search), text: 'Search'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [
          _AiChatTab(),
          _KeywordSearchTab(),
        ],
      ),
    );
  }
}

// ── AI Chat Tab ───────────────────────────────────────────────────────────────

class _ChatMessage {
  final String text;
  final bool isUser;
  _ChatMessage({required this.text, required this.isUser});
}

class _AiChatTab extends ConsumerStatefulWidget {
  const _AiChatTab();

  @override
  ConsumerState<_AiChatTab> createState() => _AiChatTabState();
}

class _AiChatTabState extends ConsumerState<_AiChatTab> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final List<_ChatMessage> _messages = [];
  bool _loading = false;

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send(String text) async {
    if (text.trim().isEmpty || _loading) return;
    _controller.clear();
    setState(() {
      _messages.add(_ChatMessage(text: text.trim(), isUser: true));
      _loading = true;
    });
    _scrollToBottom();

    final receipts = ref.read(receiptsProvider).valueOrNull ?? [];
    final currency = ref.read(displayCurrencyProvider);

    String? reply;
    if (!Env.hasSupabase) {
      reply =
          'AI assistant requires a Supabase connection. Please set up your .env file.';
    } else {
      reply = await ref
          .read(extractionServiceProvider)
          .askQuestion(
            message: text.trim(),
            receipts: receipts,
            currency: currency,
          );
      reply ??= 'I couldn\'t get a response. Please try again.';
    }

    setState(() {
      _messages.add(_ChatMessage(text: reply!, isUser: false));
      _loading = false;
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: _messages.isEmpty
              ? _WelcomeState(onSuggestion: _send)
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  itemCount: _messages.length + (_loading ? 1 : 0),
                  itemBuilder: (_, i) {
                    if (i == _messages.length) return _TypingIndicator();
                    return _Bubble(msg: _messages[i]);
                  },
                ),
        ),
        _InputBar(
          controller: _controller,
          loading: _loading,
          onSend: _send,
        ),
      ],
    );
  }
}

class _WelcomeState extends StatelessWidget {
  final void Function(String) onSuggestion;
  const _WelcomeState({required this.onSuggestion});

  static const _suggestions = [
    'How much did I spend last month?',
    'Which supplier costs me the most?',
    'What is my biggest expense category?',
    'How much have I spent on fuel?',
  ];

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      children: [
        const Icon(Icons.smart_toy_outlined,
            size: 48, color: AppTheme.brand),
        const SizedBox(height: 14),
        const Text(
          'Ask Your Business',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        const Text(
          'Ask anything about your spending, suppliers, or expenses.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFF64748B), fontSize: 14),
        ),
        const SizedBox(height: 24),
        const Align(
          alignment: Alignment.centerLeft,
          child: Text('Try asking:',
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF94A3B8),
                  fontSize: 13)),
        ),
        const SizedBox(height: 8),
        ..._suggestions.map(
          (s) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              onTap: () => onSuggestion(s),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: AppTheme.brand.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: AppTheme.brand.withValues(alpha: 0.18)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.chat_bubble_outline,
                        size: 16, color: AppTheme.brand),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(s,
                          style: const TextStyle(
                              color: AppTheme.brand,
                              fontSize: 13,
                              fontWeight: FontWeight.w500)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  final _ChatMessage msg;
  const _Bubble({required this.msg});

  @override
  Widget build(BuildContext context) {
    final isUser = msg.isUser;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.82,
        ),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isUser
              ? AppTheme.brand
              : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
          border: isUser
              ? null
              : Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Text(
          msg.text,
          style: TextStyle(
            fontSize: 14,
            height: 1.4,
            color: isUser ? Colors.white : const Color(0xFF1E293B),
          ),
        ),
      ),
    );
  }
}

class _TypingIndicator extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomRight: Radius.circular(16),
            bottomLeft: Radius.circular(4),
          ),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppTheme.brand.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(width: 8),
            const Text('Thinking…',
                style:
                    TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool loading;
  final void Function(String) onSend;
  const _InputBar(
      {required this.controller,
      required this.loading,
      required this.onSend});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          12, 8, 12, 8 + MediaQuery.of(context).padding.bottom),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              textInputAction: TextInputAction.send,
              onSubmitted: onSend,
              decoration: const InputDecoration(
                hintText: 'Ask about your spending…',
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(24)),
                  borderSide: BorderSide(color: Color(0xFFE2E8F0)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(24)),
                  borderSide: BorderSide(color: Color(0xFFE2E8F0)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(24)),
                  borderSide:
                      BorderSide(color: AppTheme.brand, width: 1.5),
                ),
                filled: true,
                fillColor: Color(0xFFF8FAFC),
              ),
            ),
          ),
          const SizedBox(width: 8),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            child: IconButton(
              onPressed:
                  loading ? null : () => onSend(controller.text),
              icon: loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppTheme.brand))
                  : const Icon(Icons.send_rounded),
              color: AppTheme.brand,
              style: IconButton.styleFrom(
                backgroundColor: AppTheme.brand.withValues(alpha: 0.10),
                shape: const CircleBorder(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Keyword Search Tab ────────────────────────────────────────────────────────

class _KeywordSearchTab extends ConsumerStatefulWidget {
  const _KeywordSearchTab();

  @override
  ConsumerState<_KeywordSearchTab> createState() =>
      _KeywordSearchTabState();
}

class _KeywordSearchTabState extends ConsumerState<_KeywordSearchTab> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final receiptsAsync = ref.watch(receiptsProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            autofocus: false,
            decoration: const InputDecoration(
              hintText: 'Search merchant, item, category…',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (v) =>
                setState(() => _query = v.trim().toLowerCase()),
          ),
        ),
        Expanded(
          child: receiptsAsync.when(
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (receipts) {
              final results = _query.isEmpty
                  ? <Receipt>[]
                  : receipts
                      .where((r) => _matches(r, _query))
                      .toList();

              if (_query.isEmpty) {
                return const Center(
                  child: Text('Type to search your receipts.',
                      style: TextStyle(color: Color(0xFF94A3B8))),
                );
              }
              if (results.isEmpty) {
                return const Center(child: Text('No matches found.'));
              }
              return ListView.builder(
                padding:
                    const EdgeInsets.fromLTRB(16, 4, 16, 100),
                itemCount: results.length,
                itemBuilder: (c, i) {
                  final r = results[i];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      onTap: () => context.push('/receipt/${r.id}'),
                      leading: CircleAvatar(
                        backgroundColor:
                            r.category.color.withValues(alpha: 0.15),
                        child: Icon(r.category.icon,
                            color: r.category.color),
                      ),
                      title: Text(r.merchant,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600)),
                      subtitle: Text(
                          '${r.category.label} · ${DateFormat.yMMMd().format(r.date)}'),
                      trailing: Text(r.total.format(),
                          style: const TextStyle(
                              fontWeight: FontWeight.w700)),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  bool _matches(Receipt r, String q) {
    if (r.merchant.toLowerCase().contains(q)) return true;
    if (r.category.label.toLowerCase().contains(q)) return true;
    if (r.items.any((it) => it.name.toLowerCase().contains(q))) return true;
    if (r.total.amount.toStringAsFixed(0).contains(q)) return true;
    return false;
  }
}
