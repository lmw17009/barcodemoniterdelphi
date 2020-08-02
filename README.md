# barcodemoniterdelphi
a pas for barcode moniter in delphixe 10.3,一个barcode监控单元，适用于delphixe 10.3
原单元只打开了数字vkcode的识别。
1，此单元目前可以适用的字符为“A..Z” “0..9” “,;_”
字符串识别为这三类的原因是目前我项目上仅可使用这几个字符串。
2，原单元有一个识别时间，我改为了二个字符间隔的时间，单位为ms 默认为1000ms，如果超过1000ms,则会进行初始化。
