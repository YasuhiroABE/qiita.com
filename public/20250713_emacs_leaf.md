---
title: Emacsのinit.elをleaf.elで書き換えた
tags:
  - Emacs
  - leaf.el
private: false
updated_at: '2026-01-08T10:29:54+09:00'
id: 23feafa7385df3ea46c3
organization_url_name: null
slide: false
ignorePublish: false
---
# はじめに

ふだん使っているemacsの設定ファイルは適当に書き換えたものを使っていたのですが、
パッケージを参照するのであればモダンな機能を利用するべきなのだろうと思っていました。

Emacsでは起動時に読み込まれる初期設定ファイルは、どの環境でも **~/.emacs.d/init.el** になっているはずです。

ちょうど現実逃避のタイミングがあったので、leaf.elを利用してみることにしました。

# 環境

* Ubuntu 24.04 (LTS)
* Emacs 29.3 (パッケージ)

# 参考資料

https://github.com/conao3/leaf.el

https://qiita.com/conao3/items/347d7e472afd0c58fbd7

https://qiita.com/conao3/items/82abfea7a4c81f946e60

# これまでのinit.elファイル

Emacsは日常的に利用していますが、使っている大きな理由は次のようなものです。

* 頻繁に繰り返す基本的な操作(コピー、ペースト、一文字削除、矩形範囲指定など)はホームポジションから指を離さずに利用したいので、Controlキーとの組み合せなどで可能なこと
* ↑に関連して日本語入力メソッドとしてSKKを利用したい
* aspellで簡易な英文スペルチェッカーとして利用したい

マウスに依存せずに作業を簡潔させたい動機が強いので、あまりEmacsを使い倒しているわけではありません。

具体的には次のような設定を行っています。

* global-set-key関数で"C-h"をdelete-backward-char関数に割り当てている
* 自分が使うモードの設定 (ddskk, adoc, markdown, etc.)
* X11関連でフォントやデフォルトサイズなどの設定

かなり前に使っていたMinimumなinit.elの内容は次のとおりです。

```lisp:~/.emacs.d/init.el
;; -*- emacs-mode  -*- ;;

;;;;;;;;;;;;;;;;;;;;;
;; global settings ;;
(setq inhibit-startup-message t)
(setq initial-scratch-message nil)

;;;;;;;;;;;;;
;; for X11 ;;
(when window-system
  (add-to-list 'default-frame-alist '(height . 36))
  (add-to-list 'default-frame-alist '(width . 120)))

;;;;;;;;;;;;;;;;;;;
;; font settings ;;
(set-default-font "Noto Sans Mono CJK JP 12") ;; mono cannot chose with 'light' word.
l
;; keyboard mappings
(global-set-key "\C-h" 'delete-backward-char)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; mode settings ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; add the default directory to the loadpath
(add-to-list 'load-path "~/lib/elisp/")

;; ispell-mode
(setq-default ispell-program-name "aspell")

;; asciidoc-mode from https://github.com/sensorflo/adoc-mode
(autoload 'adoc-mode "adoc-mode" nil t)
(add-to-list 'auto-mode-alist '("\\.adoc\\'" . adoc-mode))
;; update timestamp for adoc-mode
(add-hook 'adoc-mode-hook (lambda()
                (require 'time-stamp)
                (add-hook 'before-save-hook 'time-stamp)
                (setq time-stamp-active t)
                (setq time-stamp-start "date: ")
                (setq time-stamp-format "%04y-%02m-%02dT%02H:%02M:%02S+09:00")
                (setq time-stamp-end "$")
                ))
```

# leaf.elの導入

インストールするための設定は公式サイトなどに掲載されているとおりで、日本語でも様々な情報が入手できます。

基本となるleaf.elのひな形をコピーし、自分の環境固有の設定をleaf.el形式に変換していく流れとなります。

設定後のinit.elの内容は最後に掲載してますが、まずは作業の際に戸惑った点などについてまとめていきます。

## バイトコンパイル

参考にした資料には必ずバイトコンパイルするように記載があります。

現代の環境で設定ファイル **~/.emacs.d/init.el** をバイトコンパイルはしなくても良いのではないかと思わなくもないのですが、これを前提としている説明は多いです。

実際にバイトコンパイルしてみるといくつか警告が目につきます。

```bash:
emacs --batch -f batch-byte-compile init.el
Loading /etc/emacs/site-start.d/00debian.el (source)...
...
Loading /etc/emacs/site-start.d/50tcsh.el (source)...
Local variables list is not properly terminated

In toplevel form:
init.el:40:2: Warning: Package autoload is deprecated
init.el:88:17: Warning: reference to free variable ‘copilot-indentation-alist’
init.el:88:17: Warning: assignment to free variable ‘copilot-indentation-alist’
init.el:137:11: Warning: assignment to free variable ‘wakatime-api-key’
init.el:138:11: Warning: assignment to free variable ‘wakatime-cli-path’
init.el:152:39: Warning: assignment to free variable ‘c-basic-offset’
```

これらに対応していきます。

### "Package autoload is deprecated" 警告への対応

公式サイトのleaf.elの設定ファイルの中に記述されていますが、その中に含まれる``el-get``が原因であるためコメントアウトした設定例を公開している方もいるようです。

問題は関連する行を削除やコメントアウトしてもパッケージが残っていると警告が消えないため、``M-x package-list-packages``から``el-get``を削除することで警告は消えます。

### "assignment to free variable .." 警告への対応

leaf.elの公式サイトにも記載されていますが、適切に``:defvar ...``を記述することで警告は消えます。

```lisp:対応後のinit.elから抜粋
(leaf leaf-convert
  :defvar wakatime-api-key wakatime-cli-path
  ...
```

ここまでで一通りバイトコンパイル時のエラーメッセージには対応できました。

## パッケージの導入

自分が利用するパッケージはそれほど特殊なものはないので、個別の設定などはleaf-convertなどをうまく利用して転換していきます。

古い設定ファイルのS式を選択した状態で、``M-x leaf-convert-region-replace``を利用することで大抵の場合ではそのまま動作するコードが得られます。

例えばadoc-modeの設定は次のようにしました。

```lisp:adoc-mode関連の設定
(leaf adoc-mode
  :ensure t
  :mode ("\\.adoc\\'" . adoc-mode))
(leaf leaf-convert
  :defvar time-stamp-active time-stamp-start time-stamp-format time-stamp-end
  :config
  (add-hook 'adoc-mode-hook
        (lambda nil
          (require 'time-stamp)
          (add-hook 'before-save-hook 'time-stamp)
          (setq time-stamp-active t)
          (setq time-stamp-start "date: ")
          (setq time-stamp-format "%Y-%02m-%02dT%02H:%02M:%02S+09:00")
          (setq time-stamp-end "$"))))
```

実際には``:hook``キーワードを使って書き換えることもできるんだろうなぁと思いつつ、使っていたのは上のようなコードです。

試しに``:hook``を使ってみると、これはこれで問題なく動作しています。

```lisp:":hook"を使って書き換えてみた
(leaf adoc-mode
  :defvar time-stamp-active time-stamp-start time-stamp-format time-stamp-end
  :ensure t
  :mode ("\\.adoc\\'" . adoc-mode)
  :hook (adoc-mode-hook . (lambda nil
              (require 'time-stamp)
              (add-hook 'before-save-hook 'time-stamp)
              (setq time-stamp-active t)
              (setq time-stamp-start "date: ")
              (setq time-stamp-format "%Y-%02m-%02dT%02H:%02M:%02S+09:00")
              (setq time-stamp-end "$"))))
```

絶対的な正解はないのだろうと思いますが、こんな感じで利用しています。

# 設定ファイルの抜粋

だいたい次のような設定ファイルになりました。

前半部分の共通部分は省いています。また後半の``(provide 'init)``行も省略しています。

```lisp:~/.emacs.d/init.elの個別設定部分だけの抜粋
;; leaf-convert
(leaf leaf
  :config
  (leaf leaf-convert :ensure t)
  (leaf leaf-tree
    :ensure t
    :custom ((imenu-list-size . 30)
             (imenu-list-position . 'left))))
(leaf macrostep
  :ensure t
  :bind (("C-c e" . macrostep-expand)))

;; global system configuration
(leaf leaf-convert
  :setq ((inhibit-startup-message . t))
  :setq ((initial-scratch-message . nil)))

(leaf leaf-convert
  :bind (("" . delete-backward-char)))

(leaf leaf-convert
  :when window-system
  :config
  (add-to-list 'default-frame-alist
           '(height . 36))
  (add-to-list 'default-frame-alist
           '(width . 135))
  (add-to-list 'default-frame-alist
           '(font . "Noto Sans Mono CJK JP 12")))

;; Package Settings

(leaf ddskk
  :ensure t)

(leaf copilot
  :defvar copilot-indentation-alist
  :vc (:url "https://github.com/copilot-emacs/copilot.el")
  :config
  (leaf editorconfig
    :ensure t
    )
  (leaf s
    :ensure t
    )
  (leaf dash
    :ensure t
    )
  (add-to-list 'copilot-indentation-alist '(prog-mode 2))
  (add-to-list 'copilot-indentation-alist '(emacs-lisp-mode 2))
  (add-to-list 'copilot-indentation-alist '(special-mode 2))
  ;; specific mode to enable copilot
  (add-to-list 'copilot-indentation-alist '(yaml-mode 2))
  :hook
  (prog-mode-hook .  copilot-mode)
  :bind
  (copilot-completion-map
   ("<tab>" . copilot-accept-completion)
   ("M-f" . copilot-accept-completion-by-word)
   ("C-M-f" . copilot-accept-completion-by-paragraph)
   ("M-n" . copilot-accept-completion-by-line)
   ("C-M-n" . copilot-next-completion)
   ("C-M-p" . copilot-previous-completion)
   )
  (copilot-mode-map
   ("M-i" . copilot-complete)
   )
  )

(leaf adoc-mode
  :defvar time-stamp-active time-stamp-start time-stamp-format time-stamp-end
  :ensure t
  :mode ("\\.adoc\\'" . adoc-mode)
  :hook (adoc-mode-hook . (lambda ()
                 (require 'time-stamp)
                 (add-hook 'before-save-hook 'time-stamp)
                 (setq time-stamp-active t)
                 (setq time-stamp-start "date: ")
                 (setq time-stamp-format "%Y-%02m-%02dT%02H:%02M:%02S%:z")
                 (setq time-stamp-end "$"))))

(leaf markdown-mode
  :defvar c-basic-offset
  :ensure t
  :mode ("\\.md\\'" . markdown-mode)
  :hook (markdown-mode-hook . (lambda ()
                                (setq tab-width 4)
                                (setq indent-tabs-mode nil)
                                (setq c-basic-offset 4)
                                (setq fill-column 80)
                                (setq show-trailing-whitespace t))))
```

またバイトコンパイルのコマンドはMakefileを置いて、覚えなくて良いようにしています。

```makefile:~/.emacs.d/Makefile
.PHONY: all
all:
	emacs --batch -f batch-byte-compile init.el
```

# さいごに

設定を見直す良い機会になりましたが、感覚的にEmacsはあまり人気がないんですよね。

1995年に大学でMuleを使い始めて以来、Emacsの使い方は基本的に変化していないので経験値が引き継げて便利に思っています。

とはいえ昔の設定ファイルがそのまま使えるわけではないので、Emacsもそんなに深入りはしていません。

新しいIDE(統合開発環境)も使いますが、AtomはElectronだけ残して消えてしまったりもしましたし、IDEだけに慣れていればいいというのもやり過ぎかなと思います。

``vim``はedコマンド由来とvi由来の新しい操作の両方がVim系にも引き継がれているので、``vi``の上位互換として使っていますが、それほど深入りはしていません。

:::note
vimでCopilotモードは利用していますが、スペルチェックはしないといった感じです。
:::

自分の生産性を引き出すために、何か良く使う環境を決めて、少し勉強して出来る事を増やした方が良いでしょう。

しかし、どんな環境もそこそこ使えた方が良いと思うので、使い分けるぐらいの気持ちでいろいろ触ってみることをお勧めします。



