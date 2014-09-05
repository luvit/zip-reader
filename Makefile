all: combined

modules.zip:
	cd modules && zip -r -9 ../modules.zip . && cd ..

combined: modules.zip
	cat `which luvit` $^ > $@ && chmod +x $@

clean:
	rm -f luvit modules.zip combined
