all: combined

luvit:
	cp `which luvit` .

modules.zip:
	cd modules && zip -r -9 ../modules.zip . && cd ..

combined: luvit modules.zip
	cat $^ > $@ && chmod +x $@

clean:
	rm -f luvit modules.zip combined
