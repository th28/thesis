
import subprocess, sys
import xlwings 
import time

start_time = time.time()  

      
def save_excel_file(file_path):
    # Open the Excel file 
    excel_app = xlwings.App(visible=False)
    excel_book = excel_app.books.open(file_path)              
    excel_book.save()
    excel_book.close()
    excel_app.quit()
  
p = subprocess.Popen(["julia", 
              "C:\\Users\\Tom\\Documents\\Thesis\\dev\\model.jl"], 
              stdout=sys.stdout)    
p.communicate()

end_time = time.time()

elapsed_minutes = (end_time - start_time)/60.0
print("Run time: " + str(round(elapsed_minutes,2)) + " minutes.")

save_excel_file(file_path='C:\\Users\\Tom\\Documents\\Thesis\\dev\\RESULTS.xlsx')

