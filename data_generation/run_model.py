
import subprocess, sys
import xlwings

def save_excel_file(file_path):
    # Open the Excel file
    excel_app = xlwings.App(visible=False)
    excel_book = excel_app.books.open(file_path)
    excel_book.save()
    excel_book.close()
    excel_app.quit()

p = subprocess.Popen(["julia", 
              "C:\\Users\\Tom\\Documents\\Thesis\\dev\\test_model.jl"], 
              stdout=sys.stdout)
p.communicate()

save_excel_file(file_path='C:\\Users\\Tom\\Documents\\Thesis\\dev\\RESULTS.xlsx')