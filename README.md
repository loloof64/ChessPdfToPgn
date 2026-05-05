# ChessPdfToPgn

Convert chess pdf to pgn.

## To developpers

### Tesseract

1. You must install Tesseract

- Debian/Ubuntu/Linux Mint users

```
sudo apt-get install tesseract-ocr
sudo apt-get install tesseract-ocr-eng
```

- Mac users

```
brew install tesseract
```

- Windows users

Install installer available [https://github.com/UB-Mannheim/tesseract/wiki](on the wiki).

2. Install the trained data

3. Find the trained data folder

- Linux

```
/usr/share/tesseract-ocr/5/tessdata/
```

- Windows

```
C:\Program Files\Tesseract-OCR\tessdata\
```

- MacOs

```
/usr/local/share/tessdata/
```

4. Download the [https://github.com/tesseract-ocr/tessdata/raw/main/eng.traineddata](trained data)

5. Copy it in the previous folder (with administrator rights)

6. Check available languages for Tesseract

```
tesseract --list-langs
```

You should see **eng** in the list.
